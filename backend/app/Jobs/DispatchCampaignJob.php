<?php

namespace App\Jobs;

use App\Models\Campaign;
use App\Models\CampaignRecipient;
use App\Services\Marketing\CampaignService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldBeUnique;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

/**
 * Fan a campaign out into one job per recipient.
 *
 * Deliberately two stages. Building the audience is one query; sending is N
 * calls to Meta, any of which can fail on its own, and a single job that did
 * both would lose the whole campaign to one bad number. Here the fan-out
 * happens once and each message afterwards fails alone.
 *
 * Takes the id rather than the model so a campaign edited between queueing and
 * running is read fresh — the serialised copy would otherwise send the old one.
 */
/**
 * Unique per campaign: a second copy (double click, the recovery sweep) is
 * dropped while the first is queued or running. Recipients are also claimed
 * one by one in SendCampaignMessageJob, so even two runs never message anyone
 * twice.
 */
class DispatchCampaignJob implements ShouldQueue, ShouldBeUnique
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 3;

    public int $backoff = 60;

    /** Writing the recipient rows and queueing one job each, in chunks. */
    public int $timeout = 120;

    public int $uniqueFor = 3600;

    public function __construct(public string $campaignId)
    {
        $this->onQueue('marketing');
    }

    public function uniqueId(): string
    {
        return $this->campaignId;
    }

    public function handle(CampaignService $campaigns): void
    {
        $campaign = Campaign::with('salon', 'template')->find($this->campaignId);

        if (! $campaign) {
            return;
        }

        // Cancelled while it sat in the queue.
        if (! in_array($campaign->status, [Campaign::STATUS_SENDING, Campaign::STATUS_SCHEDULED], true)) {
            return;
        }

        if (! $campaign->template?->meta_template_name) {
            $campaign->update([
                'status' => Campaign::STATUS_FAILED,
                'failure_reason' => 'This template has not been approved by WhatsApp yet.',
                'completed_at' => now(),
            ]);

            return;
        }

        // Start it exactly once. Two copies of this job (a delayed one left in
        // the old queue, one re-queued by the recovery sweep) both get here;
        // only the one whose update changes the row fans out, the other stops
        // instead of writing the recipients a second time.
        $started = Campaign::whereKey($campaign->id)
            ->whereIn('status', [Campaign::STATUS_SENDING, Campaign::STATUS_SCHEDULED])
            ->whereNull('started_at')
            ->update(['status' => Campaign::STATUS_SENDING, 'started_at' => now()]);
        if ($started !== 1) {
            return;
        }
        $campaign->refresh();

        try {
            $sendable = $campaigns->materialiseRecipients($campaign);
        } catch (\Throwable $e) {
            Log::error('Campaign fan-out failed', ['campaign' => $campaign->id, 'error' => $e->getMessage()]);

            $campaign->update([
                'status' => Campaign::STATUS_FAILED,
                'failure_reason' => 'Could not work out who to send this to.',
                'completed_at' => now(),
            ]);

            return;
        }

        if ($sendable === 0) {
            $campaign->update([
                'status' => Campaign::STATUS_SENT,
                'completed_at' => now(),
                'failure_reason' => 'Nobody in this audience could be messaged.',
            ]);

            return;
        }

        // Spread the send rather than firing everything at once: Meta rate
        // limits per number, and a thousand simultaneous calls would mostly
        // come back as errors that look like failures to the salon.
        $index = 0;

        CampaignRecipient::where('campaign_id', $campaign->id)
            ->where('status', CampaignRecipient::STATUS_PENDING)
            ->orderBy('id')
            ->chunkById(200, function ($recipients) use (&$index) {
                foreach ($recipients as $recipient) {
                    SendCampaignMessageJob::dispatch($recipient->id)
                        ->delay(now()->addSeconds(intdiv($index, 20)));
                    $index++;
                }
            });
    }

    public function failed(\Throwable $e): void
    {
        Campaign::whereKey($this->campaignId)->update([
            'status' => Campaign::STATUS_FAILED,
            'failure_reason' => 'The campaign could not be started.',
            'completed_at' => now(),
        ]);
    }
}
