<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\SalonWorkingHour;
use App\Models\ServiceProvider;
use App\Models\User;
use App\Services\BookingPaymentService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Paying for an appointment: hold the slot, verify the payment, book.
 *
 * The point of these tests is that a booking cannot appear without a payment
 * the server itself verified, and that an unpaid hold always gives the slot
 * back.
 *
 * Runs inside a transaction so it can use the development database without
 * leaving anything behind.
 */
class BookingPaymentTest extends TestCase
{
    use DatabaseTransactions;

    public function test_booking_holds_the_slot_and_asks_for_payment(): void
    {
        [$customer, $provider, $date, $time] = $this->readyToBook();

        $response = $this->book($customer, $provider, $date, $time)->assertStatus(201);

        $response->assertJsonPath('payment_required', true);
        $this->assertNotEmpty($response->json('payment.order_id'));
        $this->assertGreaterThan(0, $response->json('payment.amount'));

        $appointment = Appointment::find($response->json('appointment.id'));
        $this->assertSame('pending_payment', $appointment->status);
        $this->assertNotNull($appointment->payment_hold_expires_at);

        // The order is on record, so the confirmation can be checked against
        // something the server wrote rather than something the app claims.
        $this->assertDatabaseHas('payment_orders', [
            'appointment_id' => $appointment->id,
            'gateway_order_id' => $response->json('payment.order_id'),
            'status' => 'created',
        ]);

        // Nothing is booked and the basket is still the customer's.
        $this->assertSame(0, Appointment::where('customer_id', $customer->id)
            ->where('status', 'scheduled')
            ->where('id', $appointment->id)
            ->count());
        $this->assertDatabaseHas('carts', [
            'customer_id' => $customer->id,
            'salon_id' => $provider->salon_id,
            'status' => 'active',
        ]);
    }

    public function test_a_verified_payment_confirms_the_booking_and_empties_the_cart(): void
    {
        [$customer, $provider, $date, $time] = $this->readyToBook();

        $booked = $this->book($customer, $provider, $date, $time)->assertStatus(201);
        $appointmentId = $booked->json('appointment.id');
        $amount = (float) $booked->json('payment.amount');

        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/payment/demo-pay")
            ->assertStatus(200)
            ->assertJsonPath('appointment.status', 'scheduled');

        $appointment = Appointment::find($appointmentId);
        $this->assertSame('scheduled', $appointment->status);
        // The hold is spent: the booking now owns the slot outright.
        $this->assertNull($appointment->payment_hold_expires_at);

        $payment = DB::table('payments')->where('appointment_id', $appointmentId)->first();
        $this->assertNotNull($payment, 'no payment was recorded');
        $this->assertSame('success', $payment->status);
        $this->assertSame('online', $payment->payment_mode);
        $this->assertEquals($amount, (float) $payment->amount);
        $this->assertNotEmpty($payment->gateway_transaction_id);

        $this->assertDatabaseHas('payment_orders', [
            'appointment_id' => $appointmentId,
            'status' => 'paid',
        ]);

        // The cart has been spent on the booking.
        $this->assertDatabaseMissing('carts', [
            'customer_id' => $customer->id,
            'salon_id' => $provider->salon_id,
            'status' => 'active',
        ]);
    }

    public function test_a_forged_signature_does_not_book_anything(): void
    {
        [$customer, $provider, $date, $time] = $this->readyToBook();

        $appointmentId = $this->book($customer, $provider, $date, $time)
            ->assertStatus(201)
            ->json('appointment.id');

        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/payment/confirm", [
                'razorpay_payment_id' => 'pay_forged_0001',
                'razorpay_signature' => str_repeat('a', 64),
            ])
            ->assertStatus(422);

        $this->assertSame('pending_payment', Appointment::find($appointmentId)->status);
        $this->assertDatabaseMissing('payments', ['appointment_id' => $appointmentId]);
    }

    public function test_confirming_twice_does_not_pay_twice(): void
    {
        [$customer, $provider, $date, $time] = $this->readyToBook();

        $appointmentId = $this->book($customer, $provider, $date, $time)
            ->assertStatus(201)
            ->json('appointment.id');

        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/payment/demo-pay")
            ->assertStatus(200);

        // A retried callback — a flaky network is the normal case, not an edge one.
        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/payment/demo-pay")
            ->assertStatus(200);

        $this->assertSame(1, DB::table('payments')->where('appointment_id', $appointmentId)->count());
    }

    public function test_an_expired_hold_gives_the_slot_back(): void
    {
        [$customer, $provider, $date, $time] = $this->readyToBook();

        $appointmentId = $this->book($customer, $provider, $date, $time)
            ->assertStatus(201)
            ->json('appointment.id');

        // The customer put their phone down on the payment sheet.
        Appointment::where('id', $appointmentId)
            ->update(['payment_hold_expires_at' => now()->subMinute()]);

        $released = app(BookingPaymentService::class)->releaseExpiredHolds();
        $this->assertGreaterThanOrEqual(1, $released);

        $appointment = Appointment::find($appointmentId);
        $this->assertSame('cancelled', $appointment->status);
        $this->assertSame('system', $appointment->cancelled_by);

        $this->assertDatabaseHas('payment_orders', [
            'appointment_id' => $appointmentId,
            'status' => 'abandoned',
        ]);

        // And the slot really is back on sale.
        $this->assertTrue(
            $this->slotIsAvailable($customer, $provider, $date, $time),
            'the released slot is still being held'
        );
    }

    public function test_backing_out_releases_the_slot_immediately(): void
    {
        [$customer, $provider, $date, $time] = $this->readyToBook();

        $appointmentId = $this->book($customer, $provider, $date, $time)
            ->assertStatus(201)
            ->json('appointment.id');

        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/payment/abandon")
            ->assertStatus(200);

        $this->assertSame('cancelled', Appointment::find($appointmentId)->status);
        $this->assertTrue($this->slotIsAvailable($customer, $provider, $date, $time));
    }

    public function test_an_unpaid_hold_is_not_shown_as_a_booking(): void
    {
        [$customer, $provider, $date, $time] = $this->readyToBook();

        $appointmentId = $this->book($customer, $provider, $date, $time)
            ->assertStatus(201)
            ->json('appointment.id');

        $listed = $this->actingAs($customer, 'sanctum')
            ->getJson('/api/customer/appointments')
            ->assertStatus(200)
            ->json();

        $ids = collect($listed['upcoming'] ?? [])->concat($listed['past'] ?? [])->pluck('id');

        $this->assertNotContains($appointmentId, $ids, 'an unpaid hold was listed as a booking');
    }

    public function test_subscription_payments_do_not_touch_the_gateway(): void
    {
        // The rule this whole feature is scoped by: Razorpay is for appointment
        // advances. Subscriptions stay on screenshot verification, so no
        // subscription request may ever carry a gateway order.
        $requests = DB::table('subscription_payment_requests')->get();

        foreach ($requests as $request) {
            $this->assertObjectNotHasProperty('gateway_order_id', $request);
        }

        $this->assertSame(
            0,
            DB::table('payment_orders')->whereNull('appointment_id')->count(),
            'a payment order exists that is not against an appointment'
        );
    }

    // ------------------------------------------------------------- fixtures

    /**
     * A customer with a cart at a salon, and a date and time they can book.
     *
     * @return array{0: User, 1: ServiceProvider, 2: string, 3: string}
     */
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

    private function slotIsAvailable(User $customer, ServiceProvider $provider, string $date, string $time): bool
    {
        foreach ($this->slots($customer, $provider, $date) as $slot) {
            if ($slot['time'] === $time) {
                return (bool) $slot['available'];
            }
        }

        return false;
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
}
