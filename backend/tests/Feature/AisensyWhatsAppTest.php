<?php

namespace Tests\Feature;

use App\Models\WhatsAppMessage;
use App\Services\Notifications\AisensyWhatsAppGateway;
use App\Support\PhoneNumber;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * Sending to AISensy.
 *
 * AISensy is the only gateway here that does not talk to Meta directly, and the
 * difference is not cosmetic: it addresses sends by *campaign* name rather than by
 * template name. There is no API call that says "send template X" — a campaign is
 * a dashboard object bound to one approved template, and its name is the routing
 * key. So most of what can go wrong is configuration going missing silently, and
 * most of what is worth asserting is the shape of the request AISensy will accept
 * or reject outright.
 *
 * The rules being pinned down, straight from their documentation:
 *  - `destination` must carry the country code, with the `+`.
 *  - `templateParams` must be exactly as long as the template's placeholders.
 *  - `media` is its own object, not a parameter, and its URL must be public.
 *
 * Runs inside a transaction because the outbox rows it inspects are real rows.
 */
class AisensyWhatsAppTest extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();

        config([
            'services.whatsapp.templates.booking_confirmed' => 'bookalook_booking_confirmed',
            'services.whatsapp.campaigns.booking_confirmed' => 'BAL_BOOKING_CONFIRMED',
        ]);
    }

    public function test_it_posts_the_documented_payload(): void
    {
        Http::fake(['backend.aisensy.com/*' => Http::response(['messageId' => 'ais-1'], 200)]);

        $message = $this->queuedMessage([
            'parameters' => ['Glow Studio', 'Sep 26, 2026 at 4:30 PM', '₹500.00'],
            'media' => ['url' => 'https://cdn.example.com/invoices/BAL-1.pdf', 'filename' => 'BAL-1.pdf'],
        ]);

        $this->gateway()->send($message);

        Http::assertSent(function ($request) {
            $body = $request->data();

            $this->assertSame('https://backend.aisensy.com/campaign/t1/api/v2', $request->url());
            $this->assertSame('key-123', $body['apiKey']);
            $this->assertSame('BAL_BOOKING_CONFIRMED', $body['campaignName']);
            $this->assertSame('bookalook', $body['source']);
            $this->assertSame(['Glow Studio', 'Sep 26, 2026 at 4:30 PM', '₹500.00'], $body['templateParams']);

            // Media travels as its own object, never as a parameter.
            $this->assertSame(
                ['url' => 'https://cdn.example.com/invoices/BAL-1.pdf', 'filename' => 'BAL-1.pdf'],
                $body['media']
            );
            $this->assertNotContains('https://cdn.example.com/invoices/BAL-1.pdf', $body['templateParams']);

            return true;
        });

        $message->refresh();
        $this->assertSame(WhatsAppMessage::STATUS_SENT, $message->status);
        $this->assertSame(AisensyWhatsAppGateway::PROVIDER, $message->provider);
        $this->assertSame('ais-1', $message->provider_message_id);
        $this->assertNotNull($message->sent_at);
        $this->assertSame(1, $message->attempts);
    }

    public function test_the_destination_carries_its_country_code(): void
    {
        Http::fake(['backend.aisensy.com/*' => Http::response([], 200)]);

        // Stored the way a person types it — no country code, leading trunk zero.
        $this->gateway()->send($this->queuedMessage([], toPhone: '09876543210'));

        Http::assertSent(fn ($request) => $request->data()['destination'] === '+919876543210');
    }

    public function test_an_unusable_number_is_refused_without_calling_the_provider(): void
    {
        Http::fake(['backend.aisensy.com/*' => Http::response([], 200)]);

        $message = $this->queuedMessage([], toPhone: '12345');

        $this->gateway()->send($message);

        // A mangled number does not fail loudly at the provider — it goes to
        // whoever those digits belong to. Better to refuse it here.
        Http::assertNothingSent();

        $message->refresh();
        $this->assertSame(WhatsAppMessage::STATUS_FAILED, $message->status);
        $this->assertStringContainsString('phone number', $message->error);
    }

    public function test_an_unconfigured_campaign_fails_loudly(): void
    {
        Http::fake(['backend.aisensy.com/*' => Http::response([], 200)]);

        // A template with no campaign behind it — the most likely misconfiguration,
        // because sending it is otherwise indistinguishable from sending it.
        config(['services.whatsapp.campaigns.booking_confirmed' => '']);

        $message = $this->queuedMessage(['parameters' => ['x']]);

        $this->gateway()->send($message);

        Http::assertNothingSent();

        $message->refresh();
        $this->assertSame(WhatsAppMessage::STATUS_FAILED, $message->status);
        $this->assertStringContainsString('WHATSAPP_CAMPAIGN', $message->error);
    }

    public function test_a_rejected_message_is_recorded_rather_than_thrown(): void
    {
        Http::fake(['backend.aisensy.com/*' => Http::response(['message' => 'Campaign is not live'], 400)]);

        $message = $this->queuedMessage(['parameters' => ['Glow Studio']]);

        // The interface contract: one bad message cannot abort a run.
        $this->gateway()->send($message);

        $message->refresh();
        $this->assertSame(WhatsAppMessage::STATUS_FAILED, $message->status);
        $this->assertSame('Campaign is not live', $message->error);
        $this->assertNotNull($message->failed_at);
    }

    public function test_a_network_failure_is_recorded_and_the_attempt_counted(): void
    {
        Http::fake(['backend.aisensy.com/*' => Http::response('', 500)]);

        $message = $this->queuedMessage(['parameters' => ['Glow Studio']]);

        $this->gateway()->send($message);

        $message->refresh();
        $this->assertSame(WhatsAppMessage::STATUS_FAILED, $message->status);
        $this->assertSame(1, $message->attempts);
    }

    public function test_a_message_with_no_media_omits_the_media_object(): void
    {
        Http::fake(['backend.aisensy.com/*' => Http::response([], 200)]);

        // AISensy rejects a text template that arrives carrying an empty media
        // object, so the key must be absent rather than blank.
        $this->gateway()->send($this->queuedMessage(['parameters' => ['Glow Studio']]));

        Http::assertSent(fn ($request) => ! array_key_exists('media', $request->data()));
    }

    public function test_parameters_are_sent_as_a_list_not_an_object(): void
    {
        Http::fake(['backend.aisensy.com/*' => Http::response([], 200)]);

        // String keys would serialise as a JSON object and come back as a
        // malformed array, which AISensy rejects on length alone.
        $this->gateway()->send($this->queuedMessage([
            'parameters' => ['salon' => 'Glow Studio', 'when' => '4:30 PM'],
        ]));

        Http::assertSent(function ($request) {
            $params = $request->data()['templateParams'];

            return array_keys($params) === [0, 1]
                && $params === ['Glow Studio', '4:30 PM'];
        });
    }

    public function test_the_campaign_is_matched_by_template_not_by_event(): void
    {
        Http::fake(['backend.aisensy.com/*' => Http::response([], 200)]);

        config([
            'services.whatsapp.templates.appointment_reminder' => 'bookalook_appointment_reminder',
            'services.whatsapp.campaigns.appointment_reminder' => 'BAL_APPOINTMENT_REMINDER',
        ]);

        $message = $this->queuedMessage(
            ['parameters' => ['Glow Studio']],
            template: 'bookalook_appointment_reminder'
        );

        $this->gateway()->send($message);

        Http::assertSent(fn ($request) => $request->data()['campaignName'] === 'BAL_APPOINTMENT_REMINDER');
    }

    // ------------------------------------------------------------- fixtures

    private function gateway(): AisensyWhatsAppGateway
    {
        return new AisensyWhatsAppGateway(
            apiKey: 'key-123',
            campaigns: config('services.whatsapp.campaigns'),
        );
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function queuedMessage(
        array $payload,
        string $toPhone = '9876543210',
        string $template = 'bookalook_booking_confirmed'
    ): WhatsAppMessage {
        return WhatsAppMessage::create([
            'user_id' => null,
            'to_phone' => $toPhone,
            'template' => $template,
            'payload' => $payload,
            'status' => WhatsAppMessage::STATUS_QUEUED,
        ]);
    }

    public function test_phone_numbers_normalise_the_way_the_provider_expects(): void
    {
        // Ten bare digits, the domestic trunk prefix, a full international
        // number, and punctuation a person actually types.
        $this->assertSame('919876543210', PhoneNumber::normalise('9876543210'));
        $this->assertSame('919876543210', PhoneNumber::normalise('09876543210'));
        $this->assertSame('919876543210', PhoneNumber::normalise('+91 98765 43210'));
        $this->assertSame('919876543210', PhoneNumber::normalise('919876543210'));

        // Too short to be a phone number, so refused rather than guessed at.
        $this->assertNull(PhoneNumber::normalise('12345'));
        $this->assertNull(PhoneNumber::normalise(''));
        $this->assertNull(PhoneNumber::normalise(null));

        $this->assertSame('+919876543210', PhoneNumber::international('9876543210'));
    }
}