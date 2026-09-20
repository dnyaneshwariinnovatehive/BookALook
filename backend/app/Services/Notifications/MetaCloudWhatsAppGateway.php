<?php

namespace App\Services\Notifications;

use App\Models\WhatsAppMessage;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * WhatsApp delivery through Meta's Cloud API.
 *
 * Meta is the only party that can say a message arrived, and it says so later,
 * over a webhook. So "sent" here means Meta accepted it — nothing more. The
 * delivered and read states are written by [WhatsAppWebhookController] when the
 * receipts come back, which is why this method never sets them.
 *
 * Per the interface contract it does not throw on ordinary provider failures.
 * One wrong number in a two-thousand-person campaign must not take the campaign
 * down with it; the failure is recorded on the row and the run continues.
 */
class MetaCloudWhatsAppGateway implements WhatsAppGateway
{
    public function __construct(
        private string $phoneNumberId,
        private string $accessToken,
        private string $apiVersion = 'v21.0',
    ) {
    }

    public function send(WhatsAppMessage $message): void
    {
        $message->increment('attempts');

        try {
            $response = Http::withToken($this->accessToken)
                ->timeout(20)
                ->post("https://graph.facebook.com/{$this->apiVersion}/{$this->phoneNumberId}/messages", [
                    'messaging_product' => 'whatsapp',
                    'to' => $message->to_phone,
                    'type' => 'template',
                    'template' => [
                        'name' => $message->template,
                        'language' => ['code' => $message->payload['language'] ?? 'en'],
                        'components' => $this->components($message),
                    ],
                ]);

            if ($response->successful()) {
                $message->forceFill([
                    'provider' => 'meta_cloud',
                    'provider_message_id' => $response->json('messages.0.id'),
                    'status' => WhatsAppMessage::STATUS_SENT,
                    'sent_at' => now(),
                    'error' => null,
                ])->save();

                return;
            }

            $this->recordFailure($message, $response->json('error.message') ?? 'WhatsApp rejected the message.');
        } catch (\Throwable $e) {
            // A network blip, not a bad message. Left recorded but retryable.
            $this->recordFailure($message, $e->getMessage());
        }
    }

    /**
     * Template parameters, in Meta's shape.
     *
     * Only the body is filled. Header and button variables would each need
     * their own component and none of the catalogue's templates use them yet —
     * when one does, this is where it grows.
     */
    private function components(WhatsAppMessage $message): array
    {
        $parameters = $message->payload['parameters'] ?? [];

        if ($parameters === []) {
            return [];
        }

        return [[
            'type' => 'body',
            'parameters' => array_map(
                fn ($value) => ['type' => 'text', 'text' => (string) $value],
                array_values($parameters)
            ),
        ]];
    }

    private function recordFailure(WhatsAppMessage $message, string $error): void
    {
        Log::warning('WhatsApp send failed', [
            'message_id' => $message->id,
            'to' => $message->to_phone,
            'error' => $error,
        ]);

        $message->forceFill([
            'provider' => 'meta_cloud',
            'status' => WhatsAppMessage::STATUS_FAILED,
            'failed_at' => now(),
            'error' => mb_substr($error, 0, 1000),
        ])->save();
    }
}
