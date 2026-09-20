<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Campaign;
use App\Models\CampaignRecipient;
use App\Models\MarketingConsent;
use App\Models\WhatsAppMessage;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

/**
 * What Meta tells us after the fact.
 *
 * Two kinds of thing arrive here. Status receipts — sent, delivered, read,
 * failed — which are the entire basis of campaign analytics, and inbound
 * replies, which matter for one reason above all: somebody writing STOP.
 *
 * The endpoint is public because Meta calls it. Authenticity comes from the
 * verify token on subscription and, for production, the X-Hub-Signature-256
 * header; it must be unauthenticated in the route table but is not unguarded.
 *
 * Every handler is best-effort and always answers 200. Meta retries anything
 * else, and a receipt we could not parse is not worth being sent the same
 * receipt for the next six hours.
 */
class WhatsAppWebhookController extends Controller
{
    /** Meta's one-time subscription handshake. */
    public function verify(Request $request)
    {
        $expected = config('services.whatsapp.verify_token');

        if ($expected && $request->query('hub_verify_token') === $expected) {
            return response($request->query('hub_challenge'), 200)
                ->header('Content-Type', 'text/plain');
        }

        return response('Forbidden', 403);
    }

    public function handle(Request $request)
    {
        if (! $this->signatureIsValid($request)) {
            Log::warning('WhatsApp webhook rejected: bad signature');

            return response()->json(['ok' => false], 403);
        }

        try {
            foreach ($request->input('entry', []) as $entry) {
                foreach ($entry['changes'] ?? [] as $change) {
                    $value = $change['value'] ?? [];

                    foreach ($value['statuses'] ?? [] as $status) {
                        $this->applyStatus($status);
                    }

                    foreach ($value['messages'] ?? [] as $message) {
                        $this->applyInbound($message);
                    }
                }
            }
        } catch (\Throwable $e) {
            Log::error('WhatsApp webhook failed', ['error' => $e->getMessage()]);
        }

        return response()->json(['ok' => true]);
    }

    /**
     * Move a message and its campaign forward.
     *
     * Receipts arrive out of order often enough to matter — a read can land
     * before the delivered that preceded it — so state only ever moves forward
     * through sent → delivered → read, never back.
     */
    private function applyStatus(array $status): void
    {
        $providerId = $status['id'] ?? null;

        if (! $providerId) {
            return;
        }

        $message = WhatsAppMessage::where('provider_message_id', $providerId)->first();

        if (! $message) {
            return;
        }

        $rank = [
            WhatsAppMessage::STATUS_QUEUED => 0,
            WhatsAppMessage::STATUS_SENT => 1,
            WhatsAppMessage::STATUS_DELIVERED => 2,
            WhatsAppMessage::STATUS_READ => 3,
        ];

        $incoming = match ($status['status'] ?? '') {
            'sent' => WhatsAppMessage::STATUS_SENT,
            'delivered' => WhatsAppMessage::STATUS_DELIVERED,
            'read' => WhatsAppMessage::STATUS_READ,
            'failed' => WhatsAppMessage::STATUS_FAILED,
            default => null,
        };

        if (! $incoming) {
            return;
        }

        if ($incoming === WhatsAppMessage::STATUS_FAILED) {
            $message->forceFill([
                'status' => WhatsAppMessage::STATUS_FAILED,
                'failed_at' => now(),
                'error' => $status['errors'][0]['title'] ?? 'Delivery failed.',
            ])->save();

            $this->syncRecipient($message, CampaignRecipient::STATUS_FAILED, 'failed_count');

            return;
        }

        if (($rank[$incoming] ?? 0) <= ($rank[$message->status] ?? 0)) {
            return;
        }

        $message->forceFill([
            'status' => $incoming,
            'sent_at' => $message->sent_at ?? now(),
            'delivered_at' => $incoming === WhatsAppMessage::STATUS_DELIVERED ? now() : $message->delivered_at,
            'read_at' => $incoming === WhatsAppMessage::STATUS_READ ? now() : $message->read_at,
        ])->save();

        $this->syncRecipient(
            $message,
            match ($incoming) {
                WhatsAppMessage::STATUS_DELIVERED => CampaignRecipient::STATUS_DELIVERED,
                WhatsAppMessage::STATUS_READ => CampaignRecipient::STATUS_READ,
                default => CampaignRecipient::STATUS_SENT,
            },
            match ($incoming) {
                WhatsAppMessage::STATUS_DELIVERED => 'delivered_count',
                WhatsAppMessage::STATUS_READ => 'read_count',
                default => null,
            }
        );
    }

    private function syncRecipient(WhatsAppMessage $message, string $status, ?string $counter): void
    {
        if (! $message->campaign_id) {
            return;
        }

        $recipient = CampaignRecipient::where('whatsapp_message_id', $message->id)->first();

        if (! $recipient || $recipient->status === $status) {
            return;
        }

        $recipient->update(['status' => $status]);

        if ($counter) {
            Campaign::whereKey($message->campaign_id)->increment($counter);
        }
    }

    /**
     * An inbound message.
     *
     * The only one acted on automatically is an opt-out. Everything else is
     * logged and left alone — a two-way inbox is a product in its own right and
     * quietly swallowing a customer's question would be worse than not
     * receiving it.
     */
    private function applyInbound(array $message): void
    {
        $from = $message['from'] ?? null;
        $body = trim(mb_strtolower($message['text']['body'] ?? ''));

        if (! $from || $body === '') {
            return;
        }

        // Meta's own opt-out words plus the ones people actually type.
        $stopWords = ['stop', 'unsubscribe', 'opt out', 'optout', 'remove me', 'band karo'];

        foreach ($stopWords as $word) {
            if ($body === $word || str_starts_with($body, $word)) {
                MarketingConsent::optOut($from);

                Log::info('WhatsApp marketing opt-out recorded', ['phone' => $from]);

                return;
            }
        }
    }

    /**
     * Meta signs every payload with the app secret.
     *
     * Skipped when no secret is configured, so a development environment can
     * receive test payloads — but the moment a secret exists it is enforced.
     */
    private function signatureIsValid(Request $request): bool
    {
        $secret = config('services.whatsapp.app_secret');

        if (! $secret) {
            return true;
        }

        $header = $request->header('X-Hub-Signature-256', '');
        $expected = 'sha256='.hash_hmac('sha256', $request->getContent(), $secret);

        return hash_equals($expected, $header);
    }
}
