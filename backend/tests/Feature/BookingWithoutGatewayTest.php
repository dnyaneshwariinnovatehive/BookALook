<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\ProviderWorkingHour;
use App\Models\Salon;
use App\Models\SalonPayout;
use App\Models\SalonWorkingHour;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceProvider;
use App\Models\ServiceTemplate;
use App\Models\User;
use App\Services\AppointmentCheckInService;
use App\Services\BookingPaymentService;
use App\Services\PayoutService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Booking with no online payment gateway (the default).
 *
 * The booking is confirmed straight away, the advance its policy asks for is
 * tracked as due, the salon (or SuperAdmin) records what is actually paid, and
 * every figure downstream — the bill at the counter, refunds, payouts — only
 * counts money that was received.
 */
class BookingWithoutGatewayTest extends TestCase
{
    use DatabaseTransactions;
    use \Tests\Feature\Concerns\ActivatesSalons;

    private User $owner;
    private User $customer;
    private Salon $salon;
    private Service $service;
    private ServiceProvider $provider;

    protected function setUp(): void
    {
        parent::setUp();

        $this->owner = $this->user('admin');
        $this->customer = $this->user('customer');
        $this->salon = $this->activateSalon(Salon::create([
            'id' => (string) Str::uuid(), 'admin_id' => $this->owner->id, 'name' => 'No Gateway Salon',
            'slug' => 'no-gateway-' . Str::random(5), 'address' => 'x', 'submitted_by' => $this->owner->id, 'status' => 'active',
        ]));

        $category = ServiceCategory::firstOrCreate(['name' => 'Hair Care'], ['id' => (string) Str::uuid(), 'is_active' => true]);
        $template = ServiceTemplate::create([
            'id' => (string) Str::uuid(), 'name' => 'Cut ' . Str::random(5), 'category_id' => $category->id,
            'estimated_duration_minutes' => 30, 'is_active' => true,
        ]);
        $this->service = Service::create([
            'id' => (string) Str::uuid(), 'salon_id' => $this->salon->id, 'template_id' => $template->id,
            'price' => 1000.0, 'duration_minutes' => 30, 'advance_percentage' => 20.0, 'is_active' => true,
        ]);

        $this->provider = ServiceProvider::create([
            'id' => (string) Str::uuid(), 'user_id' => $this->user('service_provider')->id,
            'salon_id' => $this->salon->id, 'is_active' => true,
        ]);
        $this->provider->services()->attach([$this->service->id]);

        for ($d = 0; $d <= 6; $d++) {
            SalonWorkingHour::create(['salon_id' => $this->salon->id, 'day_of_week' => $d, 'open_time' => '09:00:00', 'close_time' => '19:00:00', 'is_closed' => false]);
            ProviderWorkingHour::create(['provider_id' => $this->provider->id, 'day_of_week' => $d, 'shift_start' => '09:00:00', 'shift_end' => '19:00:00', 'is_weekly_off' => false]);
        }
    }

    private function user(string $role): User
    {
        $u = Str::random(8);

        return User::create([
            'id' => (string) Str::uuid(), 'name' => "User {$u}", 'phone' => '7' . substr((string) crc32($u), 0, 9),
            'password_hash' => bcrypt('password'), 'role' => $role, 'is_active' => true,
        ]);
    }

    private function book(): Appointment
    {
        Cart::where('customer_id', $this->customer->id)->where('status', 'active')->delete();
        $cart = Cart::create(['id' => (string) Str::uuid(), 'customer_id' => $this->customer->id, 'salon_id' => $this->salon->id, 'status' => 'active']);
        CartItem::create(['id' => (string) Str::uuid(), 'cart_id' => $cart->id, 'service_id' => $this->service->id, 'quantity' => 1]);

        $res = $this->actingAs($this->customer, 'sanctum')->postJson("/api/customer/salons/{$this->salon->id}/appointments/book", [
            'date' => Carbon::tomorrow()->toDateString(),
            'time' => '10:00',
            'provider_id' => $this->provider->id,
        ])->assertStatus(201);

        $res->assertJsonPath('payment_required', false);
        $res->assertJsonPath('pay_at_salon', true);

        return Appointment::findOrFail($res->json('appointment.id'));
    }

    public function test_a_booking_is_confirmed_straight_away_with_the_advance_due(): void
    {
        $appointment = $this->book();

        $this->assertSame('scheduled', $appointment->status);
        $this->assertNull($appointment->payment_hold_expires_at);
        $this->assertEquals(0, (float) $appointment->advance_amount, 'nothing has been paid yet');
        $this->assertEquals(200, (float) $appointment->advance_due, '20% of 1000 is due');
        $this->assertEquals(1000, (float) $appointment->balance_amount);
        $this->assertDatabaseMissing('payment_orders', ['appointment_id' => $appointment->id]);

        $summary = app(BookingPaymentService::class)->summary($appointment);
        $this->assertSame('unpaid', $summary['status']);
        $this->assertEquals(200, $summary['advance_outstanding']);

        // The booking shows on the salon's list with its payment state.
        $row = collect($this->actingAs($this->owner, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salon->id}/appointments")
            ->assertOk()->json('appointments'))->firstWhere('id', $appointment->id);
        $this->assertSame('unpaid', $row['payment']['status']);
    }

    public function test_a_payment_endpoint_cannot_confirm_anything_without_a_gateway(): void
    {
        $appointment = $this->book();

        $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointment->id}/payment/confirm", ['payment_id' => 'pay_x', 'signature' => 'sig'])
            ->assertStatus(200) // already confirmed — and no payment recorded
            ->assertJsonPath('appointment.status', 'scheduled');
        $this->assertDatabaseMissing('payments', ['appointment_id' => $appointment->id]);

        $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointment->id}/payment/demo-pay")
            ->assertStatus(404);
    }

    public function test_the_salon_records_the_advance_and_the_bill_counts_it_once(): void
    {
        $appointment = $this->book();

        $this->actingAs($this->owner, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salon->id}/appointments/{$appointment->id}/payments", [
                'amount' => 200, 'type' => 'advance', 'mode' => 'upi', 'reference' => 'UPI-1',
            ])
            ->assertCreated()
            ->assertJsonPath('summary.status', 'partially_paid')
            ->assertJsonPath('summary.advance_outstanding', 0);

        $appointment->refresh();
        $this->assertEquals(200, (float) $appointment->advance_amount);
        $this->assertEquals(800, (float) $appointment->balance_amount);

        // At the counter: only the remaining 800 is asked for.
        $appointment->forceFill(['status' => 'in_progress'])->save();
        $checkIn = app(AppointmentCheckInService::class);
        $bill = $checkIn->bill($appointment->fresh($checkIn->relations()));
        $this->assertEquals(200, $bill['advance_paid']);
        $this->assertEquals(800, $bill['balance_due']);

        $checkIn->collectPaymentAndComplete($appointment->fresh($checkIn->relations()), 'cash', $this->owner);
        $summary = app(BookingPaymentService::class)->summary($appointment->fresh());
        $this->assertSame('paid', $summary['status']);
        $this->assertEquals(1000, $summary['paid']);
    }

    public function test_nobody_can_record_more_than_is_owed_or_at_another_salon(): void
    {
        $appointment = $this->book();

        $this->actingAs($this->owner, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salon->id}/appointments/{$appointment->id}/payments", [
                'amount' => 1500, 'type' => 'full', 'mode' => 'cash',
            ])
            ->assertStatus(422);

        $stranger = $this->user('admin');
        $this->actingAs($stranger, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salon->id}/appointments/{$appointment->id}/payments", [
                'amount' => 100, 'type' => 'advance', 'mode' => 'cash',
            ])
            ->assertForbidden();
    }

    public function test_cancelling_after_paying_the_salon_leaves_a_refund_for_the_salon_to_return(): void
    {
        // This service gives its advance back on cancellation.
        $this->service->forceFill(['will_refund_advance_if_cancelled' => true])->save();
        $appointment = $this->book();
        app(BookingPaymentService::class)->recordPayment($appointment, 200, 'advance', 'cash', $this->owner->id);

        $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointment->id}/cancel")
            ->assertOk();

        $refund = DB::table('payment_refunds')->where('appointment_id', $appointment->id)->first();
        $this->assertNotNull($refund, 'the refundable advance is on record');
        $this->assertSame(BookingPaymentService::REFUND_AWAITING_MANUAL, $refund->status);
        $this->assertSame('salon', json_decode($refund->metadata, true)['returned_by']);

        $this->actingAs($this->owner, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salon->id}/appointments/{$appointment->id}/refunds/{$refund->id}/returned", ['reference' => 'cash back'])
            ->assertOk();
        $this->assertSame('processed', DB::table('payment_refunds')->where('id', $refund->id)->value('status'));
    }

    public function test_an_old_online_payment_is_refunded_by_hand_and_superadmin_marks_it(): void
    {
        // This service gives its advance back on cancellation.
        $this->service->forceFill(['will_refund_advance_if_cancelled' => true])->save();
        $appointment = $this->book();
        // A payment taken online before the gateway was removed.
        $paymentId = (string) Str::uuid();
        DB::table('payments')->insert([
            'id' => $paymentId, 'appointment_id' => $appointment->id, 'amount' => 200, 'currency' => 'INR',
            'payment_type' => 'advance', 'payment_mode' => 'online', 'gateway' => 'online_gateway',
            'gateway_transaction_id' => 'pay_old_1', 'status' => 'success', 'paid_at' => now(),
            'created_at' => now(), 'updated_at' => now(),
        ]);
        $appointment->forceFill(['advance_amount' => 200, 'balance_amount' => 800])->save();

        $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointment->id}/cancel")
            ->assertOk();

        $refund = DB::table('payment_refunds')->where('appointment_id', $appointment->id)->first();
        $this->assertSame(BookingPaymentService::REFUND_AWAITING_MANUAL, $refund->status);
        $this->assertSame('bookalook', json_decode($refund->metadata, true)['returned_by']);

        // The salon cannot mark BookALook's refund; SuperAdmin can.
        $this->actingAs($this->owner, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salon->id}/appointments/{$appointment->id}/refunds/{$refund->id}/returned")
            ->assertStatus(422);

        $superadmin = $this->user('superadmin');
        $this->actingAs($superadmin, 'sanctum')
            ->postJson("/api/superadmin/appointments/{$appointment->id}/refunds/{$refund->id}/returned", ['reference' => 'NEFT-9'])
            ->assertOk()
            ->assertJsonPath('summary.refunded', 200);
    }

    public function test_superadmin_sees_and_records_payments(): void
    {
        $appointment = $this->book();
        $superadmin = $this->user('superadmin');

        $this->actingAs($superadmin, 'sanctum')
            ->postJson("/api/superadmin/appointments/{$appointment->id}/payments", ['amount' => 1000, 'type' => 'full', 'mode' => 'bank_transfer'])
            ->assertCreated()
            ->assertJsonPath('summary.status', 'paid')
            ->assertJsonPath('payments.0.source', 'recorded');

        $this->assertDatabaseHas('audit_log', ['action' => 'booking.payment_recorded']);
    }

    public function test_money_the_salon_took_never_counts_as_held_by_bookalook(): void
    {
        $appointment = $this->book();
        app(BookingPaymentService::class)->recordPayment($appointment, 200, 'advance', 'upi', $this->owner->id);
        $appointment->forceFill(['status' => 'completed', 'completed_at' => now(), 'final_billed_amount' => 1000])->save();

        $date = Carbon::parse($appointment->appointment_date);
        $payout = app(PayoutService::class)->calculate($this->salon->id, $date->copy()->startOfWeek(), $date->copy()->endOfWeek());

        if ($payout->exists) {
            $this->assertEquals(0, (float) SalonPayout::find($payout->id)->gross_amount, 'the advance went to the salon, not BookALook');
        } else {
            $this->assertTrue(true, 'nothing held, so no payout row');
        }
    }

    public function test_a_full_payment_rule_makes_the_whole_price_due(): void
    {
        \App\Models\PlatformPolicySetting::updateOrCreate(['setting_key' => 'customer_cancellation_limit'], ['setting_value' => '1', 'data_type' => 'integer', 'description' => 'x']);
        \App\Models\PlatformPolicySetting::updateOrCreate(['setting_key' => 'customer_limit_action'], ['setting_value' => 'full_payment', 'data_type' => 'string', 'description' => 'x']);

        $first = $this->book();
        $this->actingAs($this->customer, 'sanctum')->postJson("/api/customer/appointments/{$first->id}/cancel")->assertOk();

        $second = $this->book();
        $this->assertEquals(1000, (float) $second->advance_due, 'full amount due before the visit');
        $this->assertEquals(0, (float) $second->advance_amount);
        $this->assertSame('full_upfront', $second->payment_option);
    }
}
