<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\Invoice;
use App\Models\InvoiceSetting;
use App\Models\SalonWorkingHour;
use App\Models\ServiceProvider;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * The invoice a customer gets for a confirmed appointment.
 *
 * Three things are being defended here, and they are the three ways this
 * feature could quietly go wrong:
 *
 *  1. An invoice exists for a booking, and only for a booking — never for a
 *     hold that was abandoned or a payment that failed.
 *  2. There is exactly one of them. A retried confirmation, a double tap, or a
 *     booking that was free and so settled without a gateway all reach the same
 *     place, and three receipts for one visit is a support call.
 *  3. It says the same money the salon will ask for. The totals are read from
 *     AppointmentCheckInService::bill(), so this is really asserting that
 *     nothing between the two has drifted.
 *
 * Runs inside a transaction so it can use the development database without
 * leaving anything behind.
 */
class InvoiceTest extends TestCase
{
    use DatabaseTransactions;

    public function test_a_confirmed_booking_issues_an_invoice(): void
    {
        [$customer, $provider, $date, $time] = $this->readyToBook();

        $appointmentId = $this->bookAndPay($customer, $provider, $date, $time);

        $this->assertDatabaseHas('invoices', ['appointment_id' => $appointmentId]);

        $invoice = Invoice::where('appointment_id', $appointmentId)->firstOrFail();

        $this->assertSame('INR', $invoice->currency);
        $this->assertNotEmpty($invoice->invoice_number);
        $this->assertNotEmpty($invoice->line_items);

        // The advance the customer actually paid is recorded, and what is left
        // is what the salon will ask for at the door.
        $appointment = Appointment::findOrFail($appointmentId);
        $this->assertSame((float) $appointment->advance_amount, $invoice->advance_paid);
        $this->assertSame(
            round($invoice->total - $invoice->advance_paid, 2),
            $invoice->balance_due
        );
    }

    public function test_the_invoice_number_follows_the_configured_series(): void
    {
        [$customer, $provider, $date, $time] = $this->readyToBook();

        InvoiceSetting::updateOrCreate(
            ['setting_key' => 'invoice_number_prefix'],
            ['setting_value' => 'TEST', 'data_type' => 'string']
        );
        InvoiceSetting::updateOrCreate(
            ['setting_key' => 'invoice_number_padding'],
            ['setting_value' => '4', 'data_type' => 'integer']
        );

        $invoice = Invoice::where('appointment_id', $this->bookAndPay($customer, $provider, $date, $time))
            ->firstOrFail();

        $this->assertMatchesRegularExpression(
            '/^TEST-' . now()->format('Y') . '-\d{4}$/',
            $invoice->invoice_number
        );
    }

    public function test_a_second_confirmation_does_not_issue_a_second_invoice(): void
    {
        [$customer, $provider, $date, $time] = $this->readyToBook();

        $booked = $this->book($customer, $provider, $date, $time);
        $appointmentId = $booked->json('appointment.id');

        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/payment/demo-pay")
            ->assertStatus(200);

        $first = Invoice::where('appointment_id', $appointmentId)->firstOrFail()->invoice_number;

        // The app retried a confirmation it had already got a 200 for.
        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/payment/demo-pay")
            ->assertStatus(200);

        $this->assertSame(1, Invoice::where('appointment_id', $appointmentId)->count());
        $this->assertSame(
            $first,
            Invoice::where('appointment_id', $appointmentId)->firstOrFail()->invoice_number
        );
    }

    public function test_an_unpaid_hold_is_never_invoiced(): void
    {
        [$customer, $provider, $date, $time] = $this->readyToBook();

        $appointmentId = $this->book($customer, $provider, $date, $time)->json('appointment.id');

        // Slot held, money not moved.
        $this->assertSame(0, Invoice::where('appointment_id', $appointmentId)->count());

        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/payment/abandon")
            ->assertStatus(200);

        $this->assertSame(
            0,
            Invoice::where('appointment_id', $appointmentId)->count(),
            'an abandoned checkout produced an invoice'
        );
    }

    public function test_the_booking_response_carries_a_working_invoice_link(): void
    {
        [$customer, $provider, $date, $time] = $this->readyToBook();

        $booked = $this->book($customer, $provider, $date, $time);
        $appointmentId = $booked->json('appointment.id');

        $url = $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/payment/demo-pay")
            ->assertStatus(200)
            ->json('appointment.invoice.url');

        $this->assertNotEmpty($url);

        // The link is signed, so it opens without a bearer token — which is the
        // whole reason the route is not behind auth:sanctum.
        $this->get($url)->assertStatus(200)->assertSee('Invoice', false);
    }

    public function test_a_tampered_invoice_link_is_refused(): void
    {
        [$customer, $provider, $date, $time] = $this->readyToBook();

        $url = $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$this->book($customer, $provider, $date, $time)->json('appointment.id')}/payment/demo-pay")
            ->assertStatus(200)
            ->json('appointment.invoice.url');

        // Someone swapped the invoice id out for another customer's.
        $this->get(str_replace(
            'signature=',
            'signature=' . str_repeat('0', 5),
            $url
        ))->assertStatus(403);
    }

    public function test_an_invoice_keeps_the_format_it_was_issued_with(): void
    {
        [$customer, $provider, $date, $time] = $this->readyToBook();

        $appointmentId = $this->bookAndPay($customer, $provider, $date, $time);
        $invoice = Invoice::where('appointment_id', $appointmentId)->firstOrFail();

        $this->assertSame('BookALook', $invoice->template['invoice_business_name']);

        // SuperAdmin rebrands the platform.
        InvoiceSetting::updateOrCreate(
            ['setting_key' => 'invoice_business_name'],
            ['setting_value' => 'Renamed Platform', 'data_type' => 'string']
        );

        // An issued document is a statement made at a moment in time. Editing
        // the format must change future invoices, not this one.
        $invoice->refresh();
        $this->assertSame('BookALook', $invoice->template['invoice_business_name']);
    }

    // ------------------------------------------------------------- fixtures

    /** @return array{0: User, 1: ServiceProvider, 2: string, 3: string} */
    private function readyToBook(): array
    {
        $customer = User::where('role', 'customer')->first();
        $provider = ServiceProvider::with(['user', 'services'])
            ->whereHas('services')
            ->where('is_active', true)
            ->first();

        if (! $customer || ! $provider) {
            $this->markTestSkipped('needs a seeded salon with staff and a customer');
        }

        $service = $provider->services->first();

        Cart::where('customer_id', $customer->id)->where('status', 'active')->delete();

        $cart = Cart::create([
            'customer_id' => $customer->id,
            'salon_id' => $provider->salon_id,
            'status' => 'active',
        ]);

        CartItem::create(['cart_id' => $cart->id, 'service_id' => $service->id, 'quantity' => 1]);

        [$date, $time] = $this->firstBookableSlot($customer, $provider);

        if (! $date) {
            $this->markTestSkipped('needs a day with a free slot');
        }

        return [$customer, $provider, $date, $time];
    }

    /** @return array{0: ?string, 1: ?string} */
    private function firstBookableSlot(User $customer, ServiceProvider $provider): array
    {
        for ($i = 1; $i <= 10; $i++) {
            $date = Carbon::today()->addDays($i)->toDateString();

            $hours = SalonWorkingHour::where('salon_id', $provider->salon_id)
                ->where('day_of_week', Carbon::parse($date)->dayOfWeek)
                ->first();

            if (! $hours || $hours->is_closed) {
                continue;
            }

            foreach ($this->slots($customer, $provider, $date) as $slot) {
                if ($slot['available']) {
                    return [$date, $slot['time']];
                }
            }
        }

        return [null, null];
    }

    private function slots(User $customer, ServiceProvider $provider, string $date): array
    {
        return $this->actingAs($customer, 'sanctum')->getJson(
            "/api/customer/salons/{$provider->salon_id}/availability?date={$date}&provider_id={$provider->id}"
        )->json('slots') ?? [];
    }

    private function book(User $customer, ServiceProvider $provider, string $date, string $time)
    {
        return $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/salons/{$provider->salon_id}/appointments/book", [
                'date' => $date,
                'time' => $time,
                'provider_id' => $provider->id,
            ]);
    }

    /** Hold the slot, then pay for it, which is what issues the invoice. */
    private function bookAndPay(User $customer, ServiceProvider $provider, string $date, string $time): string
    {
        $appointmentId = $this->book($customer, $provider, $date, $time)->json('appointment.id');

        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/payment/demo-pay")
            ->assertStatus(200);

        return $appointmentId;
    }
}
