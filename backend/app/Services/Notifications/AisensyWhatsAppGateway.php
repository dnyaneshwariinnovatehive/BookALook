<?php

namespace App\Services\Notifications;

use App\Models\WhatsAppMessage;
use App\Support\PhoneNumber;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * WhatsApp delivery through AISensy.
 *
 * AISensy is an aggregator sitting in front of Meta's official WhatsApp Business
 * API, and it differs from talking to Meta directly in one way that shapes this
 * whole class: it routes on a **campaign**, not on a template. A campaign is
 * created in the AISensy dashboard against one approved template and switched
 * live, and the name of that campaign is what a request must quote. There is no
 * API call that sends "template X" — the campaign is the unit of sending.
 *
 * So the campaign names are configuration, one per event, and this class maps the
 * template recorded on the outbox row to the campaign that wraps it. Events
 * without a configured campaign fail loudly rather than being quietly dropped:
 * a missing campaign is an operator mistake, and a message that never arrives is
 * exactly the thing nobody notices until a customer complains.
 *
 * Media — the invoice PDF — travels in its own `media` object rather than as a
 * template parameter, and AISensy fetches the URL server-side. That URL must
 * therefore be publicly reachable, which is why the PDF is uploaded to the media
 * disk rather than served off the app's own disk.
 *
 * Per the interface contract, ordinary provider failures are recorded on the row
 * and never thrown, so one undeliverable number cannot abort a run.
 */
class AisensyWhatsAppGateway implements WhatsAppGateway
{
    /** AISensy's own identifier for this integration, recorded on every row. */
    public const PROVIDER = 'aisensy';

    /** Where every send goes. Overridable so tests can point it elsewhere. */
    private const ENDPOINT = '/campaign/t1/api/v2';

    /**
     * Meta template name => AISensy campaign name.
     *
     * Built once from the two config blocks rather than looked up per send. Both
     * are keyed by event, so pairing them produces the lookup this class needs
     * without inventing a second naming scheme.
     *
     * @var array<string, string>
     */
    private readonly array $campaignByTemplate;

    /**
     * @param  array<string, string>  $campaigns  Event => AISensy campaign name.
     */
    public function __construct(
        private readonly string $apiKey,
        array $campaigns,
        private readonly string $baseUrl = 'https://backend.aisensy.com',
        private readonly string $source = 'bookalook',
        private readonly int $timeout = 20,
    ) {
        $this->campaignByTemplate = $this->pairWithTemplates($campaigns);
    }

    public function send(WhatsAppMessage $message): void
    {
        $message->increment('attempts');

        $campaign = $this->campaignByTemplate[$message->template] ?? null;

        if ($campaign === null) {
            $this->recordFailure(
                $message,
                "No AISensy campaign is configured for template '{$message->template}'. "
                .'Set WHATSAPP_CAMPAIGN_* to the name of the live API campaign in AISensy.'
            );

            return;
        }

        $destination = PhoneNumber::international($message->to_phone);

        if ($destination === null) {
            $this->recordFailure($message, 'Recipient number could not be read as a phone number.');

            return;
        }

        try {
            $response = Http::timeout($this->timeout)
                ->acceptJson()
                ->post(rtrim($this->baseUrl, '/').self::ENDPOINT, $this->payload($message, $campaign, $destination));

            if ($response->successful()) {
                $message->forceFill([
                    'provider' => self::PROVIDER,
                    'provider_message_id' => $this->providerMessageId($response),
                    'status' => WhatsAppMessage::STATUS_SENT,
                    'sent_at' => now(),
                    'error' => null,
                ])->save();

                return;
            }

            $this->recordFailure($message, $this->errorMessage($response));
        } catch (\Throwable $e) {
            // A network blip, not a bad message. Left recorded but retryable.
            $this->recordFailure($message, $e->getMessage());
        }
    }

    /**
     * The request body, in AISensy's documented shape.
     *
     * `templateParams` has to be exactly as long as the placeholders in the
     * campaign's template or the request is rejected outright, so the values are
     * cast to strings and re-indexed from zero — a payload built with string keys
     * would serialise as an object and come back as a malformed array.
     *
     * @return array<string, mixed>
     */
    private function payload(WhatsAppMessage $message, string $campaign, string $destination): array
    {
        $body = [
            'apiKey' => $this->apiKey,
            'campaignName' => $campaign,
            'destination' => $destination,
            'userName' => $this->userName($message),
            'source' => $this->source,
        ];

        $params = $message->payload['parameters'] ?? [];

        if ($params !== []) {
            $body['templateParams'] = array_map(
                static fn ($value) => (string) $value,
                array_values((array) $params)
            );
        }

        // Only sent when present. An empty media object is not the same as no
        // media, and a text template would be rejected for having one.
        $media = $message->payload['media'] ?? null;

        if (is_array($media) && filled($media['url'] ?? null)) {
            $body['media'] = [
                'url' => (string) $media['url'],
                'filename' => (string) ($media['filename'] ?? 'invoice.pdf'),
            ];
        }

        $attributes = $message->payload['attributes'] ?? null;

        if (is_array($attributes) && $attributes !== []) {
            $body['attributes'] = $attributes;
        }

        return $body;
    }

    /**
     * Pair each configured campaign with the Meta template its event uses.
     *
     * AISensy campaigns are addressed by name and never mention templates, while
     * the outbox records the template. Joining the two config blocks here is what
     * lets a send be written in terms of the event the business cares about.
     *
     * Events whose template name is blank are dropped: an unconfigured campaign
     * must read as "not configured", not as "configured with an empty name".
     *
     * @param  array<string, string>  $campaigns
     * @return array<string, string>
     */
    private function pairWithTemplates(array $campaigns): array
    {
        $templates = (array) config('services.whatsapp.templates', []);
        $pairs = [];

        foreach ($campaigns as $event => $campaign) {
            $template = trim((string) ($templates[$event] ?? ''));
            $campaign = trim((string) $campaign);

            if ($template !== '' && $campaign !== '') {
                $pairs[$template] = $campaign;
            }
        }

        return $pairs;
    }

    /**
     * A name for the contact, so the message is traceable in the AISensy
     * dashboard rather than being an anonymous row against a number.
     *
     * Falls back to the number itself rather than being omitted — AISensy wants
     * something here, and a contact labelled with its own number is still a
     * contact a human can identify when debugging a campaign.
     */
    private function userName(WhatsAppMessage $message): string
    {
        $name = $message->payload['user_name'] ?? null;

        if (filled($name)) {
            return (string) $name;
        }

        $name = $message->user?->name;

        return filled($name) ? (string) $name : (string) $message->to_phone;
    }

    /**
     * Pull the provider's message id out of the response.
     *
     * AISensy's exact success shape is not pinned down by its public docs, so
     * the plausible locations are tried in turn. Null is an acceptable outcome —
     * the message genuinely was accepted, and a missing id only costs us the
     * ability to match a later delivery receipt back to this row.
     */
    private function providerMessageId(Response $response): ?string
    {
        foreach (['messageId', 'message_id', 'data.messageId', 'data.message_id', 'data.id', 'id'] as $key) {
            $value = data_get($response->json(), $key);

            if (filled($value)) {
                return (string) $value;
            }
        }

        return null;
    }

    /**
     * The provider's explanation, in the few shapes AISensy has used.
     */
    private function errorMessage(Response $response): string
    {
        foreach (['message', 'error.message', 'error', 'data.message'] as $key) {
            $value = data_get($response->json(), $key);

            if (is_string($value) && $value !== '') {
                return $value;
            }
        }

        return 'AISensy rejected the message with HTTP '.$response->status().'.';
    }

    private function recordFailure(WhatsAppMessage $message, string $error): void
    {
        Log::warning('WhatsApp send failed', [
            'provider' => self::PROVIDER,
            'message_id' => $message->id,
            'to' => $message->to_phone,
            'template' => $message->template,
            'error' => $error,
        ]);

        $message->forceFill([
            'provider' => self::PROVIDER,
            'status' => WhatsAppMessage::STATUS_FAILED,
            'failed_at' => now(),
            'error' => mb_substr($error, 0, 1000),
        ])->save();
    }
}