<?php

namespace App\Jobs;

use App\Models\Campaign;
use App\Models\CampaignRecipient;
use App\Services\Marketing\CampaignService;
use Illuminate\Bus\Queueable;
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
class DispatchCampaignJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 3;

    public function __construct(public string $campaignId)
    {
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

        $campaign->update(['status' => Campaign::STATUS_SENDING, 'started_at' => now()]);

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
