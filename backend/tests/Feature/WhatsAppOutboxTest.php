<?php

namespace Tests\Feature;

use App\Jobs\SendWhatsAppMessageJob;
use App\Models\Appointment;
use App\Models\Invoice;
use App\Models\InvoiceSetting;
use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Models\User;
use App\Models\WhatsAppMessage;
use App\Services\InvoicePdfService;
use App\Services\Notifications\NotificationService;
use App\Services\Notifications\WhatsAppGateway;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\Bus;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Str;
use Tests\Support\FakesCloudinaryUpload;
use Tests\TestCase;

/**
 * The WhatsApp outbox: how a message gets from a booking to a provider.
 *
 * Two things are being defended here.
 *
 * The first is that sending is *queued*, not inline. The booking confirmation
 * carries an invoice, and rendering and uploading a PDF inside the request that
 * confirmed the booking would hold that request open for the length of a
 * document render and a network round trip — on the one code path where the
 * customer is watching a spinner and the money has already moved.
 *
 * The second is that nothing gets stranded. A message can be left `queued` in
 * three ways that all look identical in the database: the provider was not
 * configured yet, the queue was down, or a dispatch threw and the caller logged
 * it rather than failing the booking. In all three cases the row looks like it
 * is merely waiting, which is why the drain exists.
 */
class WhatsAppOutboxTest extends TestCase
{
    use DatabaseTransactions;
    use FakesCloudinaryUpload;

    private ?Appointment $appointment = null;

    public function test_every_message_carries_the_placeholders_its_template_expects(): void
    {
        Bus::fake([SendWhatsAppMessageJob::class]);

        $appointment = $this->appointment();
        $notifications = app(NotificationService::class);

        $notifications->bookingConfirmed($appointment, 'Glow Studio', 'Sep 26, 2026 at 4:30 PM');
        $notifications->appointmentReminder($appointment, 'Glow Studio', 'Sep 26, 2026 at 4:30 PM', 'reminder-1');
        $notifications->bookingCancelled($appointment, 'Glow Studio', 'Sep 26, 2026 at 4:30 PM');
        $notifications->appointmentNeedsReschedule($appointment, 'Glow Studio', 'Sep 26, 2026 at 4:30 PM', 'Staff illness');

        $messages = WhatsAppMessage::whereIn('template', [
            config('services.whatsapp.templates.booking_confirmed'),
            config('services.whatsapp.templates.appointment_reminder'),
            config('services.whatsapp.templates.appointment_cancelled'),
            config('services.whatsapp.templates.salon_closure'),
        ])->get();

        $this->assertCount(4, $messages, 'all four events should reach the outbox');

        foreach ($messages as $message) {
            $parameters = $message->payload['parameters'] ?? null;

            // Both gateways build their request body from `parameters`, so a
            // message without it is not a shorter message — it is one that goes
            // out with every placeholder in the approved template left blank.
            $this->assertIsArray(
                $parameters,
                "{$message->template} has no parameters, so its template renders blank"
            );
            $this->assertNotEmpty($parameters, "{$message->template} has no parameters to send");

            // AISensy rejects a template whose parameter count does not match its
            // placeholders, and string keys serialise as an object rather than the
            // ordered array it expects.
            $this->assertSame(range(0, count($parameters) - 1), array_keys($parameters));
            $this->assertSame(
                $parameters,
                array_map('strval', $parameters),
                "{$message->template} has a parameter that is not a string"
            );
        }
    }

    public function test_a_closure_with_no_stated_reason_still_fills_its_placeholder(): void
    {
        Bus::fake([SendWhatsAppMessageJob::class]);

        app(NotificationService::class)->appointmentNeedsReschedule(
            $this->appointment(),
            'Glow Studio',
            'Sep 26, 2026 at 4:30 PM',
            null
        );

        $message = WhatsAppMessage::where('template', config('services.whatsapp.templates.salon_closure'))->firstOrFail();

        $this->assertCount(3, $message->payload['parameters']);
        $this->assertNotSame('', trim($message->payload['parameters'][2]));
    }

    public function test_a_confirmation_does_not_send_inline(): void
    {
        Bus::fake([SendWhatsAppMessageJob::class]);
        Http::fake();

        $appointment = $this->appointment();

        app(NotificationService::class)
            ->bookingConfirmed($appointment, 'Glow Studio', 'Sep 26, 2026 at 4:30 PM');

        // The provider must not have been called during the request.
        Http::assertNothingSent();

        Bus::assertDispatched(
            SendWhatsAppMessageJob::class,
            fn (SendWhatsAppMessageJob $job) => true
        );
    }

    public function test_a_confirmation_names_the_invoice_as_its_attachment(): void
    {
        Bus::fake([SendWhatsAppMessageJob::class]);

        $appointment = $this->appointment();

        app(NotificationService::class)
            ->bookingConfirmed($appointment, 'Glow Studio', 'Sep 26, 2026 at 4:30 PM');

        $message = WhatsAppMessage::where('related_appointment_id', $appointment->id)
            ->where('template', config('services.whatsapp.templates.booking_confirmed'))
            ->firstOrFail();

        // The invoice is named, not resolved: at this point in the booking it does
        // not exist yet, and the job renders it.
        $this->assertSame('invoice', $message->payload['attachment']);
        $this->assertSame(WhatsAppMessage::STATUS_QUEUED, $message->status);
    }

    public function test_the_job_attaches_the_invoice_pdf_before_sending(): void
    {
        // The upload goes through the Cloudinary SDK now, so Storage::fake() no
        // longer intercepts it — without this the test would upload to the real
        // account named in .env.
        $this->fakeCloudinaryUpload();

        // The job resolves the gateway through the container, so the driver has to
        // be switched here rather than the gateway injected — otherwise the test
        // would pass through whichever provider the environment happens to use.
        config([
            'services.whatsapp.driver' => 'aisensy',
            'services.whatsapp.aisensy.api_key' => 'key-123',
            'services.whatsapp.campaigns.booking_confirmed' => 'BAL_BOOKING_CONFIRMED',
        ]);
        Http::fake(['backend.aisensy.com/*' => Http::response([], 200)]);

        $appointment = $this->appointment();

        $invoice = Invoice::create([
            'appointment_id' => $appointment->id,
            'invoice_number' => 'BAL-TEST-'.Str::upper(Str::random(8)),
            'issued_at' => now(),
            'bill_to_name' => 'Asha',
            'salon_name' => 'Glow Studio',
            'provider_name' => 'Riya',
            'appointment_date' => $appointment->appointment_date,
            'start_time' => $appointment->start_time,
            'end_time' => $appointment->end_time,
            'line_items' => [['name' => 'Haircut', 'kind' => 'service', 'price' => 500, 'duration_minutes' => 45]],
            'subtotal' => 500,
            'advance_paid' => 500,
            'balance_due' => 0,
            'total' => 500,
            'template' => InvoiceSetting::typed(),
        ]);

        $message = WhatsAppMessage::create([
            'to_phone' => '9876543210',
            'template' => config('services.whatsapp.templates.booking_confirmed'),
            'payload' => ['parameters' => ['Glow Studio'], 'attachment' => 'invoice'],
            'related_appointment_id' => $appointment->id,
            'status' => WhatsAppMessage::STATUS_QUEUED,
        ]);

        (new SendWhatsAppMessageJob($message->id))->handle(
            app(WhatsAppGateway::class),
            app(InvoicePdfService::class),
        );

        Http::assertSent(function ($request) use ($invoice) {
            $media = $request->data()['media'] ?? null;

            $this->assertIsArray($media, 'the invoice PDF should have been attached');
            $this->assertStringEndsWith('.pdf', $media['url']);

            // The filename the customer sees has to be recognisable as their own
            // document, so it is the invoice number rather than something generic.
            $this->assertSame($invoice->invoice_number.'.pdf', $media['filename']);

            return true;
        });
    }

    public function test_the_job_skips_a_message_that_has_already_gone_out(): void
    {
        Http::fake(['backend.aisensy.com/*' => Http::response([], 200)]);

        $message = WhatsAppMessage::create([
            'to_phone' => '9876543210',
            'template' => 'bookalook_booking_confirmed',
            'payload' => ['parameters' => ['Glow Studio']],
            'status' => WhatsAppMessage::STATUS_SENT,
        ]);

        (new SendWhatsAppMessageJob($message->id))->handle(
            app(WhatsAppGateway::class),
            app(InvoicePdfService::class),
        );

        // A retried job must not send a second time.
        Http::assertNothingSent();
        $this->assertSame(0, $message->refresh()->attempts);
    }

    public function test_the_drain_command_dispatches_stranded_messages(): void
    {
        Queue::fake();
        $this->withASendingDriver();

        $message = WhatsAppMessage::create([
            'to_phone' => '9876543210',
            'template' => 'bookalook_booking_confirmed',
            'payload' => ['parameters' => ['Glow Studio']],
            'status' => WhatsAppMessage::STATUS_QUEUED,
        ]);

        // Old enough to count as stranded rather than merely in flight.
        $message->forceFill(['created_at' => now()->subHour()])->save();

        $this->artisan('app:drain-whatsapp-outbox')->assertSuccessful();

        Queue::assertPushed(
            SendWhatsAppMessageJob::class,
            fn (SendWhatsAppMessageJob $job) => $job->messageId === $message->id
        );
    }

    public function test_the_drain_command_leaves_a_fresh_message_alone(): void
    {
        Queue::fake();
        $this->withASendingDriver();

        $message = WhatsAppMessage::create([
            'to_phone' => '9876543210',
            'template' => 'bookalook_booking_confirmed',
            'payload' => ['parameters' => ['Glow Studio']],
            'status' => WhatsAppMessage::STATUS_QUEUED,
        ]);

        $this->artisan('app:drain-whatsapp-outbox')->assertSuccessful();

        // Written seconds ago is a message the queue worker already owns. Taking
        // it here as well is how a customer ends up with the same message twice.
        Queue::assertNotPushed(SendWhatsAppMessageJob::class);
    }

    public function test_the_drain_command_leaves_a_message_a_provider_already_has_alone(): void
    {
        Queue::fake();
        $this->withASendingDriver();

        $message = WhatsAppMessage::create([
            'to_phone' => '9876543210',
            'template' => 'bookalook_booking_confirmed',
            'payload' => ['parameters' => ['Glow Studio']],
            'status' => WhatsAppMessage::STATUS_QUEUED,
            // Counted by the gateway on its way out. Still `queued` because the
            // send has not finished, not because it was lost.
            'attempts' => 1,
        ]);

        $message->forceFill(['created_at' => now()->subHour()])->save();

        $this->artisan('app:drain-whatsapp-outbox')->assertSuccessful();

        // Handing this out again is how the customer gets the same message twice.
        Queue::assertNotPushed(SendWhatsAppMessageJob::class);
    }

    public function test_the_drain_command_does_nothing_on_the_log_driver(): void
    {
        Queue::fake();

        // Pinned rather than assumed: .env may name a real provider, and this test
        // is about what the command does when it cannot send.
        config(['services.whatsapp.driver' => 'log']);

        // The log driver is the default, and it leaves rows `queued` on purpose.
        $message = WhatsAppMessage::create([
            'to_phone' => '9876543210',
            'template' => 'bookalook_booking_confirmed',
            'payload' => ['parameters' => ['Glow Studio']],
            'status' => WhatsAppMessage::STATUS_QUEUED,
        ]);

        $message->forceFill(['created_at' => now()->subHour()])->save();

        $this->artisan('app:drain-whatsapp-outbox')
            ->expectsOutputToContain('log driver')
            ->assertSuccessful();

        // Every pass would end with the row still queued, so the backlog would look
        // exactly like a stuck queue and the log would fill with no-ops.
        Queue::assertNotPushed(SendWhatsAppMessageJob::class);
    }

    public function test_the_log_driver_backlog_is_still_released_once_a_provider_exists(): void
    {
        Queue::fake();
        $this->withASendingDriver();

        // A row written while the log driver was in use: queued, never attempted.
        $message = WhatsAppMessage::create([
            'to_phone' => '9876543210',
            'template' => 'bookalook_booking_confirmed',
            'payload' => ['parameters' => ['Glow Studio']],
            'status' => WhatsAppMessage::STATUS_QUEUED,
        ]);

        $message->forceFill(['created_at' => now()->subHour()])->save();

        $this->artisan('app:drain-whatsapp-outbox')->assertSuccessful();

        // The reason the command exists at all: switching providers must not
        // strand whatever was written while the old one was in use.
        Queue::assertPushed(
            SendWhatsAppMessageJob::class,
            fn (SendWhatsAppMessageJob $job) => $job->messageId === $message->id
        );
    }

    /**
     * Point the container at a provider that actually sends, which is the
     * precondition for every drain assertion below.
     */
    private function withASendingDriver(): void
    {
        config([
            'services.whatsapp.driver' => 'aisensy',
            'services.whatsapp.aisensy.api_key' => 'key-123',
        ]);
    }

    public function test_the_drain_command_ignores_a_message_that_has_already_failed(): void
    {
        Queue::fake();
        $this->withASendingDriver();

        $message = WhatsAppMessage::create([
            'to_phone' => '9876543210',
            'template' => 'bookalook_booking_confirmed',
            'payload' => ['parameters' => ['Glow Studio']],
            'status' => WhatsAppMessage::STATUS_FAILED,
        ]);

        $message->forceFill(['created_at' => now()->subHour()])->save();

        $this->artisan('app:drain-whatsapp-outbox')->assertSuccessful();

        // Failed means the provider said no. Retrying forever would be a loop, not
        // a recovery.
        Queue::assertNotPushed(SendWhatsAppMessageJob::class);
    }

    public function test_the_drain_command_is_a_no_op_when_the_outbox_is_empty(): void
    {
        Queue::fake();
        $this->withASendingDriver();

        $this->artisan('app:drain-whatsapp-outbox')
            ->expectsOutputToContain('No queued WhatsApp messages')
            ->assertSuccessful();
    }

    // ------------------------------------------------------------- fixtures

    /**
     * A booked appointment on a real salon.
     *
     * Built rather than borrowed from the demo seed, because these tests should
     * hold on a database nobody has seeded. The chain is only as long as the
     * foreign keys force: an appointment belongs to a salon, a salon to an admin,
     * and an appointment must name the staff member actually serving it.
     */
    private function appointment(): Appointment
    {
        // Per instance, not static: DatabaseTransactions rolls the rows back after
        // each test, so an id cached across tests would point at a row that no
        // longer exists.
        if ($this->appointment) {
            return $this->appointment;
        }

        // Unique suffixes so repeated runs never collide on the unique phone and
        // slug columns.
        $unique = substr(bin2hex(random_bytes(6)), 0, 10);

        $admin = User::create([
            'name' => "Outbox Admin {$unique}",
            'phone' => '9'.substr((string) crc32("admin{$unique}"), 0, 9),
            'password_hash' => 'x',
            'role' => 'admin',
            'is_active' => true,
        ]);

        $customer = User::create([
            'name' => "Outbox Customer {$unique}",
            'phone' => '9'.substr((string) crc32("cust{$unique}"), 0, 9),
            'password_hash' => 'x',
            'role' => 'customer',
            'is_active' => true,
        ]);

        $salon = Salon::create([
            'admin_id' => $admin->id,
            'name' => "Glow Studio {$unique}",
            'slug' => "glow-studio-{$unique}",
            'address' => '12 FC Road, Pune 411001',
            'phone_num' => '9876543210',
            'submitted_by' => $admin->id,
            'status' => 'active',
        ]);

        $staffUser = User::create([
            'name' => "Outbox Staff {$unique}",
            'phone' => '8'.substr((string) crc32("staff{$unique}"), 0, 9),
            'password_hash' => 'x',
            'role' => 'service_provider',
            'is_active' => true,
        ]);

        $staff = ServiceProvider::create([
            'user_id' => $staffUser->id,
            'salon_id' => $salon->id,
            'base_salary' => 0,
            'commission_percentage' => 0,
            'auto_approve_leave' => false,
            'is_active' => true,
        ]);

        return $this->appointment = Appointment::create([
            'customer_id' => $customer->id,
            'salon_id' => $salon->id,
            'appointed_provider_id' => $staff->id,
            'appointment_date' => now()->addDay()->toDateString(),
            'start_time' => '10:00',
            'end_time' => '11:00',
            'status' => 'confirmed',
            'payment_option' => 'advance_only',
            'total_amount' => 500,
            'advance_amount' => 500,
            'balance_amount' => 0,
        ]);
    }
}
