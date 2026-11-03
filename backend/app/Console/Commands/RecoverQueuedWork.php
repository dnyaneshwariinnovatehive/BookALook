<?php

namespace App\Console\Commands;

use App\Jobs\DispatchCampaignJob;
use App\Jobs\RetryPendingPushDeliveryJob;
use App\Jobs\SendCampaignMessageJob;
use App\Jobs\SendPushNotificationJob;
use App\Models\Campaign;
use App\Models\CampaignRecipient;
use App\Models\Notification;
use App\Models\NotificationDelivery;
use App\Models\WhatsAppMessage;
use App\Support\SafeDispatch;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

/**
 * Re-queues work that PostgreSQL says is owed but no queue is carrying.
 *
 * The queue (Redis) is only the transport; the rows are the record. A job can
 * be lost — the queue was down when it was dispatched, a worker was killed,
 * Redis restarted — and this finds what such a loss leaves behind:
 *
 *  1. push      notifications.push_queued_at set, push_done_at empty, over 5
 *               minutes old. Re-queued at most 3 times, then given up (logged).
 *  2. retries   notification_deliveries `pending` and untouched for 5 minutes
 *               (their retry job was lost). Re-queued until 6 attempts / 24 h.
 *  3. whatsapp  `queued` with attempts > 0 for 15 minutes: the send started and
 *               never recorded a result. NOT re-sent (it may have arrived);
 *               failed as "outcome unknown" so it is visible. (Never-attempted
 *               rows are app:drain-whatsapp-outbox's job, unchanged.)
 *  4. campaigns scheduled campaigns past their time, and started campaigns
 *               with recipients still pending well after their pacing ended.
 *
 * Every re-queue first claims the row with a conditional update, so two
 * overlapping runs never queue the same thing twice, and every job re-checks
 * the row before acting. Runs every minute (routes/console.php).
 */
class RecoverQueuedWork extends Command
{
    protected $signature = 'app:recover-queued-work {--dry-run : Report what would be recovered, change nothing}';

    protected $description = 'Re-queue pushes, push retries and campaign sends that PostgreSQL shows as owed but no queue is carrying';

    private const STALE_MINUTES = 5;
    private const MAX_PUSH_SWEEPS = 3;
    private const MAX_DELIVERY_ATTEMPTS = 6;
    private const LIMIT = 200;

    private bool $dry = false;

    public function handle(): int
    {
        $this->dry = (bool) $this->option('dry-run');

        $counts = [
            'push' => $this->pushes(),
            'push_retries' => $this->pendingDeliveries(),
            'whatsapp_unknown' => $this->interruptedWhatsApp(),
            'campaigns' => $this->campaigns(),
            'campaign_recipients' => $this->campaignRecipients(),
        ];

        foreach ($counts as $what => $n) {
            $this->line(sprintf('%-20s %d', $what, $n));
        }
        if (array_sum($counts) > 0 && ! $this->dry) {
            Log::info('queue.recovered', $counts);
        }

        return self::SUCCESS;
    }

    private function pushes(): int
    {
        $stale = now()->subMinutes(self::STALE_MINUTES);
        $rows = Notification::query()
            ->whereNull('push_done_at')
            ->whereNotNull('push_queued_at')
            ->where('push_queued_at', '<=', $stale)
            ->orderBy('push_queued_at')
            ->limit(self::LIMIT)
            ->get(['id', 'push_queued_at', 'push_sweeps', 'created_at']);

        $n = 0;
        foreach ($rows as $row) {
            if ($this->dry) {
                $n++;
                continue;
            }

            $giveUp = $row->push_sweeps >= self::MAX_PUSH_SWEEPS || $row->created_at < now()->subDay();
            $claimed = Notification::whereKey($row->id)
                ->whereNull('push_done_at')
                ->where('push_queued_at', $row->push_queued_at)
                ->update($giveUp
                    ? ['push_done_at' => now()]
                    : ['push_queued_at' => now(), 'push_sweeps' => $row->push_sweeps + 1]);

            if ($claimed !== 1) {
                continue;
            }
            if ($giveUp) {
                Log::error('queue.push_given_up', ['notification_id' => $row->id, 'sweeps' => $row->push_sweeps]);
                continue;
            }

            SafeDispatch::afterCommit(new SendPushNotificationJob($row->id), ['notification_id' => $row->id, 'via' => 'recovery']);
            $n++;
        }

        return $n;
    }

    private function pendingDeliveries(): int
    {
        $rows = NotificationDelivery::query()
            ->where('status', NotificationDelivery::STATUS_PENDING)
            ->where('updated_at', '<=', now()->subMinutes(self::STALE_MINUTES))
            ->orderBy('updated_at')
            ->limit(self::LIMIT)
            ->get(['id', 'updated_at', 'attempt_count', 'created_at']);

        $n = 0;
        foreach ($rows as $row) {
            if ($this->dry) {
                $n++;
                continue;
            }

            $giveUp = $row->attempt_count >= self::MAX_DELIVERY_ATTEMPTS || $row->created_at < now()->subDay();
            $claimed = NotificationDelivery::whereKey($row->id)
                ->where('status', NotificationDelivery::STATUS_PENDING)
                ->where('updated_at', $row->updated_at)
                ->update($giveUp
                    ? ['status' => NotificationDelivery::STATUS_FAILED, 'failed_at' => now(), 'updated_at' => now(),
                        'failure_reason' => 'Still pending after its retries were lost; given up by the recovery sweep.']
                    : ['updated_at' => now()]);

            if ($claimed !== 1 || $giveUp) {
                continue;
            }

            SafeDispatch::afterCommit(new RetryPendingPushDeliveryJob($row->id), ['delivery_id' => $row->id, 'via' => 'recovery']);
            $n++;
        }

        return $n;
    }

    private function interruptedWhatsApp(): int
    {
        $query = WhatsAppMessage::query()
            ->where('status', WhatsAppMessage::STATUS_QUEUED)
            ->where('attempts', '>', 0)
            ->where('updated_at', '<=', now()->subMinutes(15));

        if ($this->dry) {
            return $query->count();
        }

        $n = $query->limit(self::LIMIT)->update([
            'status' => WhatsAppMessage::STATUS_FAILED,
            'failed_at' => now(),
            'error' => WhatsAppMessage::OUTCOME_UNKNOWN,
            'updated_at' => now(),
        ]);
        if ($n > 0) {
            Log::warning('queue.whatsapp_outcome_unknown', ['count' => $n]);
        }

        return $n;
    }

    /** Scheduled past their time, or marked sending but never started. */
    private function campaigns(): int
    {
        $stale = now()->subMinutes(self::STALE_MINUTES);
        $ids = Campaign::query()
            ->whereNull('started_at')
            ->where(fn ($q) => $q
                ->where(fn ($s) => $s->where('status', Campaign::STATUS_SCHEDULED)->where('scheduled_for', '<=', $stale))
                ->orWhere(fn ($s) => $s->where('status', Campaign::STATUS_SENDING)->where('updated_at', '<=', $stale)))
            ->limit(self::LIMIT)
            ->pluck('id');

        if (! $this->dry) {
            // Unique per campaign, and the job claims the start itself.
            foreach ($ids as $id) {
                SafeDispatch::afterCommit(new DispatchCampaignJob($id), ['campaign_id' => $id, 'via' => 'recovery']);
            }
        }

        return $ids->count();
    }

    /**
     * Started campaigns whose pacing (20 sends a second) ended over 10 minutes
     * ago but which still have pending recipients: their send jobs were lost.
     * Each recipient is claimed by its job, so a duplicate does nothing.
     */
    private function campaignRecipients(): int
    {
        $campaigns = Campaign::query()
            ->where('status', Campaign::STATUS_SENDING)
            ->whereNotNull('started_at')
            ->where('started_at', '<=', now()->subMinutes(10))
            ->get(['id', 'started_at']);

        $n = 0;
        foreach ($campaigns as $campaign) {
            $pending = CampaignRecipient::where('campaign_id', $campaign->id)
                ->where('status', CampaignRecipient::STATUS_PENDING);
            $total = CampaignRecipient::where('campaign_id', $campaign->id)->count();
            $pacingEnds = $campaign->started_at->copy()->addSeconds(intdiv($total, 20) + 600);
            if ($pacingEnds->isFuture()) {
                continue;
            }

            foreach ($pending->orderBy('id')->limit(self::LIMIT)->pluck('id') as $i => $recipientId) {
                if (! $this->dry) {
                    SafeDispatch::afterCommit(
                        (new SendCampaignMessageJob($recipientId))->delay(now()->addSeconds(intdiv($i, 20))),
                        ['campaign_recipient_id' => $recipientId, 'via' => 'recovery'],
                    );
                }
                $n++;
            }
        }

        return $n;
    }
}
