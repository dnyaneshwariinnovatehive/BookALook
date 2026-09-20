<?php

namespace App\Jobs;

use App\Models\Campaign;
use App\Models\CampaignRecipient;
use App\Models\MarketingConsent;
use App\Models\WhatsAppMessage;
use App\Services\Notifications\WhatsAppGateway;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\DB;

/**
 * One marketing message to one person.
 *
 * Consent is checked again here, not just when the audience was built. Between
 * the fan-out and this job running, someone may have replied STOP — and the
 * whole point of honouring an opt-out is that it takes effect immediately, not
 * once the current campaign has finished going out.
 */
class SendCampaignMessageJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 2;

    public function __construct(public string $recipientId)
    {
    }

    public function handle(WhatsAppGateway $gateway): void
    {
        $recipient = CampaignRecipient::with('campaign.template', 'campaign.salon')->find($this->recipientId);

        if (! $recipient || $recipient->status !== CampaignRecipient::STATUS_PENDING) {
            return;
        }

        $campaign = $recipient->campaign;
        $template = $campaign?->template;

        if (! $campaign || ! $template) {
            return;
        }

        // The late opt-out check.
        $optedOut = MarketingConsent::where('phone', $recipient->phone)
            ->where('status', MarketingConsent::STATUS_OUT)
            ->exists();

        if ($optedOut) {
            $recipient->update([
                'status' => CampaignRecipient::STATUS_SKIPPED,
                'skip_reason' => CampaignRecipient::SKIP_OPTED_OUT,
            ]);

            $campaign->increment('skipped_count');

            return;
        }

        $message = WhatsAppMessage::create([
            'user_id' => $recipient->user_id,
            'to_phone' => $recipient->phone,
            'template' => $template->meta_template_name,
            'category' => WhatsAppMessage::CATEGORY_MARKETING,
            'payload' => [
                'language' => $template->language,
                // Meta numbers placeholders from 1 in declaration order.
                'parameters' => $template->orderedValues($recipient->variables ?? []),
                'campaign_name' => $campaign->name,
            ],
            'related_salon_id' => $campaign->salon_id,
            'campaign_id' => $campaign->id,
            'status' => WhatsAppMessage::STATUS_QUEUED,
        ]);

        $recipient->update([
            'whatsapp_message_id' => $message->id,
            'status' => CampaignRecipient::STATUS_QUEUED,
        ]);

        $gateway->send($message);

        $message->refresh();

        // The gateway owns delivery state; this only mirrors it onto the
        // recipient so campaign totals can be read without a join.
        $this->reflect($recipient, $campaign, $message);
    }

    private function reflect(CampaignRecipient $recipient, Campaign $campaign, WhatsAppMessage $message): void
    {
        DB::transaction(function () use ($recipient, $campaign, $message) {
            match ($message->status) {
                WhatsAppMessage::STATUS_SENT,
                WhatsAppMessage::STATUS_DELIVERED,
                WhatsAppMessage::STATUS_READ => tap($recipient)
                    ->update(['status' => CampaignRecipient::STATUS_SENT])
                    && $campaign->increment('sent_count'),

                WhatsAppMessage::STATUS_FAILED => tap($recipient)
                    ->update(['status' => CampaignRecipient::STATUS_FAILED])
                    && $campaign->increment('failed_count'),

                // Still queued: no provider is configured, so the row waits for
                // one rather than being called a success.
                default => null,
            };

            $this->closeIfFinished($campaign->fresh());
        });
    }

    /** Mark the campaign done once nothing is left pending or queued. */
    private function closeIfFinished(Campaign $campaign): void
    {
        if ($campaign->status !== Campaign::STATUS_SENDING) {
            return;
        }

        $outstanding = CampaignRecipient::where('campaign_id', $campaign->id)
            ->whereIn('status', [CampaignRecipient::STATUS_PENDING, CampaignRecipient::STATUS_QUEUED])
            ->exists();

        if (! $outstanding) {
            $campaign->update(['status' => Campaign::STATUS_SENT, 'completed_at' => now()]);
        }
    }

    public function failed(\Throwable $e): void
    {
        $recipient = CampaignRecipient::find($this->recipientId);

        if (! $recipient) {
            return;
        }

        $recipient->update(['status' => CampaignRecipient::STATUS_FAILED]);
        Campaign::whereKey($recipient->campaign_id)->increment('failed_count');
    }
}
