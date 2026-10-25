<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\AppointmentService as AppointmentLine;
use App\Models\PlatformPolicySetting;
use App\Models\ProviderWorkingHour;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\SalonWorkingHour;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceProvider;
use App\Models\ServiceTemplate;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Services\AppointmentCheckInService;
use App\Support\BillingModel;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The money flaws found walking a booking from search to completion: the
 * first-time discount lost at the counter, a full upfront payment counted twice
 * so extras came out free, payments left behind on a rescheduled booking, and
 * complete / no-show working on any booking at any time.
 */
class BookingMoneyFlawsTest extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow(Carbon::today()->setTime(12, 0));

        PlatformPolicySetting::updateOrCreate(
            ['setting_key' => 'appointment_start_early_minutes'],
            ['setting_value' => '30', 'data_type' => 'integer']
        );
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    public function test_the_counter_bill_keeps_the_first_time_discount(): void
    {
        [$salon, $admin, $customer, $provider] = $this->fixture();
        // A 1000 service with a 200 first-time discount; 30% advance on 800 = 240.
        $appointment = $this->booking($salon, $customer, $provider, total: 800, advance: 240, discount: 200);

        $this->start($admin, $salon, $appointment);

        $bill = $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/bill")
            ->assertOk()
            ->json('bill');

        $this->assertEquals(800.0, $bill['total']);
        $this->assertEquals(560.0, $bill['balance_due']);
        $this->assertEquals(800.0, $bill['lines'][0]['price']);
    }

    public function test_adding_an_extra_keeps_the_discount_in_the_total(): void
    {
        [$salon, $admin, $customer, $provider] = $this->fixture();
        $appointment = $this->booking($salon, $customer, $provider, total: 800, advance: 240, discount: 200);
        $this->start($admin, $salon, $appointment);

        $extra = $provider->services->first();
        app(AppointmentCheckInService::class)->addExtraService($appointment->fresh(), $extra, $provider->id, $admin);

        $this->assertEquals(1800.0, (float) $appointment->fresh()->total_amount);
    }

    public function test_an_extra_is_charged_when_the_booking_was_paid_in_full_online(): void
    {
        [$salon, $admin, $customer, $provider] = $this->fixture();
        $appointment = $this->booking($salon, $customer, $provider, total: 1000, advance: 1000);
        $this->paidOnline($appointment, 1000, 'full');
        $this->start($admin, $salon, $appointment);

        $extra = $provider->services->first();
        app(AppointmentCheckInService::class)->addExtraService($appointment->fresh(), $extra, $provider->id, $admin);

        $bill = $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/bill")
            ->assertOk()
            ->json('bill');

        $this->assertEquals(1000.0, $bill['balance_due']);
    }

    public function test_complete_refuses_a_booking_that_was_never_started(): void
    {
        [$salon, $admin, $customer, $provider] = $this->fixture();

        foreach (['scheduled', 'cancelled', 'no_show', 'pending_payment'] as $status) {
            $appointment = $this->booking($salon, $customer, $provider, total: 1000, advance: 300);
            $appointment->forceFill(['status' => $status])->save();

            $this->actingAs($admin, 'sanctum')
                ->postJson("/api/partner/appointments/{$appointment->id}/complete")
                ->assertStatus(422);

            $this->assertSame($status, $appointment->fresh()->status);
            $this->assertSame(0, DB::table('payments')->where('appointment_id', $appointment->id)->count());
        }
    }

    public function test_complete_still_finishes_a_started_session(): void
    {
        [$salon, $admin, $customer, $provider] = $this->fixture();
        $appointment = $this->booking($salon, $customer, $provider, total: 1000, advance: 300);
        $this->start($admin, $salon, $appointment);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/appointments/{$appointment->id}/complete")
            ->assertOk();

        $this->assertSame('completed', $appointment->fresh()->status);
    }

    public function test_no_show_waits_for_the_booking_time(): void
    {
        [$salon, $admin, $customer, $provider] = $this->fixture();
        $appointment = $this->booking($salon, $customer, $provider, total: 1000, advance: 300, start: '18:00:00');

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/appointments/{$appointment->id}/no-show")
            ->assertStatus(422);
        $this->assertSame('scheduled', $appointment->fresh()->status);

        Carbon::setTestNow(Carbon::today()->setTime(18, 5));

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/appointments/{$appointment->id}/no-show")
            ->assertOk();
        $this->assertSame('no_show', $appointment->fresh()->status);
    }

    public function test_no_show_refuses_a_finished_or_cancelled_booking(): void
    {
        [$salon, $admin, $customer, $provider] = $this->fixture();

        foreach (['completed', 'cancelled', 'in_progress'] as $status) {
            $appointment = $this->booking($salon, $customer, $provider, total: 1000, advance: 300);
            $appointment->forceFill(['status' => $status])->save();

            $this->actingAs($admin, 'sanctum')
                ->postJson("/api/partner/appointments/{$appointment->id}/no-show")
                ->assertStatus(422);

            $this->assertSame($status, $appointment->fresh()->status);
        }
    }

    public function test_a_reschedule_takes_the_payment_and_recipient_with_it(): void
    {
        [$salon, , $customer, $provider] = $this->fixture();
        $tomorrow = Carbon::tomorrow()->toDateString();

        $appointment = $this->booking($salon, $customer, $provider, total: 1000, advance: 300, date: $tomorrow);
        $appointment->forceFill([
            'booked_for' => 'other',
            'recipient_name' => 'Aarav',
            'recipient_gender' => 'male',
        ])->save();
        $paymentId = $this->paidOnline($appointment, 300, 'advance');

        $replacementId = $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointment->id}/reschedule", [
                'date' => $tomorrow,
                'time' => '15:00',
                'provider_id' => $provider->id,
            ])
            ->assertOk()
            ->json('appointment.id');

        $this->assertSame($replacementId, DB::table('payments')->where('id', $paymentId)->value('appointment_id'));

        $replacement = Appointment::find($replacementId);
        $this->assertSame('other', $replacement->booked_for);
        $this->assertSame('Aarav', $replacement->recipient_name);
        $this->assertSame('male', $replacement->recipient_gender);
    }

    public function test_a_visit_left_in_progress_is_closed_a_day_later(): void
    {
        [$salon, $admin, $customer, $provider] = $this->fixture();
        $appointment = $this->booking($salon, $customer, $provider, total: 1000, advance: 300);
        $this->start($admin, $salon, $appointment);

        Carbon::setTestNow(now()->addHours(23));
        $this->artisan('app:close-stale-sessions')->assertSuccessful();
        $this->assertSame('in_progress', $appointment->fresh()->status);

        Carbon::setTestNow(now()->addHours(2));
        $this->artisan('app:close-stale-sessions')->assertSuccessful();

        $appointment->refresh();
        $this->assertSame('completed', $appointment->status);
        $this->assertSame('cash', $appointment->payment_mode);
        $this->assertEquals(700.0, (float) DB::table('payments')
            ->where('appointment_id', $appointment->id)->whereNull('gateway')->sum('amount'));
    }

    public function test_a_salon_whose_plan_lapsed_takes_no_new_bookings(): void
    {
        [$salon, , $customer, $provider] = $this->fixture();
        SalonSubscription::where('salon_id', $salon->id)->update([
            'end_date' => Carbon::today()->subDays(2),
            'status' => 'expired',
        ]);

        $service = $provider->services->first();

        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/salons/{$salon->id}/cart/items", ['service_id' => $service->id])
            ->assertStatus(409)
            ->assertJsonPath('salon_unavailable', true);

        $this->actingAs($customer, 'sanctum')
            ->getJson("/api/customer/salons/{$salon->id}/availability?date=" . Carbon::tomorrow()->toDateString() . "&provider_id={$provider->id}")
            ->assertStatus(409);

        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/salons/{$salon->id}/appointments/book", [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '15:00',
                'provider_id' => $provider->id,
            ])
            ->assertStatus(409);
    }

    // ------------------------------------------------------------- fixtures

    /**
     * A salon of its own (owner, one provider working 9 to 7 every day, one
     * 1000 service) and a customer, built inside the test transaction.
     */
    private function fixture(): array
    {
        $uuid = fn () => (string) Str::uuid();
        $phone = fn () => '9' . random_int(100000000, 999999999);

        $admin = User::create(['id' => $uuid(), 'name' => 'Money Owner', 'phone' => $phone(),
            'password_hash' => bcrypt('x'), 'role' => 'admin', 'is_active' => true]);
        $customer = User::create(['id' => $uuid(), 'name' => 'Money Customer', 'phone' => $phone(),
            'password_hash' => bcrypt('x'), 'role' => 'customer', 'is_active' => true]);
        $staff = User::create(['id' => $uuid(), 'name' => 'Money Staff', 'phone' => $phone(),
            'password_hash' => bcrypt('x'), 'role' => 'service_provider', 'is_active' => true]);

        $salon = Salon::create(['id' => $uuid(), 'admin_id' => $admin->id, 'name' => 'Money Salon',
            'slug' => 'money-salon-' . Str::random(6), 'address' => '1 Test St', 'status' => 'active',
            'submitted_by' => $admin->id]);

        // Staff screens sit behind the plan check, so the salon needs a live plan.
        $plan = SubscriptionPlan::first() ?? SubscriptionPlan::create([
            'name' => 'Money Plan', 'price' => 1999, 'validity_days' => 30, 'is_active' => true,
        ]);
        SalonSubscription::create(['salon_id' => $salon->id, 'plan_id' => $plan->id,
            'billing_type' => BillingModel::SUBSCRIPTION, 'plan_price_snapshot' => $plan->price,
            'start_date' => Carbon::today()->subDay(), 'end_date' => Carbon::today()->addDays(30),
            'status' => 'active']);

        $provider = ServiceProvider::create(['id' => $uuid(), 'user_id' => $staff->id,
            'salon_id' => $salon->id, 'is_active' => true]);

        for ($d = 0; $d <= 6; $d++) {
            SalonWorkingHour::create(['salon_id' => $salon->id, 'day_of_week' => $d,
                'open_time' => '09:00:00', 'close_time' => '19:00:00', 'is_closed' => false]);
            ProviderWorkingHour::create(['provider_id' => $provider->id, 'day_of_week' => $d,
                'shift_start' => '09:00:00', 'shift_end' => '19:00:00', 'is_weekly_off' => false]);
        }

        $category = ServiceCategory::firstOrCreate(['name' => 'Money Care'],
            ['id' => $uuid(), 'is_active' => true]);
        $template = ServiceTemplate::firstOrCreate(['name' => 'Money Cut'],
            ['id' => $uuid(), 'category_id' => $category->id, 'is_active' => true, 'estimated_duration_minutes' => 30]);
        $service = Service::create(['id' => $uuid(), 'salon_id' => $salon->id,
            'template_id' => $template->id, 'price' => 1000, 'duration_minutes' => 30,
            'advance_percentage' => 30, 'is_active' => true]);
        $provider->services()->attach($service->id);
        $provider->load(['user', 'services.template', 'salon']);

        return [$salon, $admin, $customer, $provider];
    }

    private function booking(
        Salon $salon,
        User $customer,
        ServiceProvider $provider,
        float $total,
        float $advance,
        float $discount = 0,
        string $start = '10:00:00',
        ?string $date = null,
    ): Appointment {
        $service = $provider->services->first();
        $token = 'test-' . bin2hex(random_bytes(8));

        $appointment = Appointment::create([
            'salon_id' => $salon->id,
            'customer_id' => $customer->id,
            'appointed_provider_id' => $provider->id,
            'booking_source' => 'online',
            'appointment_date' => $date ?? Carbon::today()->toDateString(),
            'start_time' => $start,
            'end_time' => Carbon::parse($start)->addMinutes(30)->format('H:i:s'),
            'status' => 'scheduled',
            'payment_option' => $advance >= $total ? 'full_upfront' : 'advance_only',
            'total_amount' => $total,
            'advance_amount' => $advance,
            'balance_amount' => $total - $advance,
            'first_time_discount_amount' => $discount,
            'qr_token_hash' => hash('sha256', $token),
            'qr_generated_at' => now(),
            'qr_expires_at' => Carbon::today()->endOfDay(),
        ]);

        AppointmentLine::create([
            'appointment_id' => $appointment->id,
            'service_id' => $service->id,
            'price_at_booking' => $total + $discount,
            'original_service_price' => $service->price,
            'first_time_discount_amount' => $discount,
            'duration_minutes_at_booking' => 30,
            'line_status' => 'booked',
        ]);

        return $appointment->fresh();
    }

    private function start(User $admin, Salon $salon, Appointment $appointment): void
    {
        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/start", ['manual' => true])
            ->assertOk();
    }

    private function paidOnline(Appointment $appointment, float $amount, string $type): string
    {
        $id = (string) Str::uuid();

        DB::table('payments')->insert([
            'id' => $id,
            'appointment_id' => $appointment->id,
            'amount' => $amount,
            'currency' => 'INR',
            'payment_type' => $type,
            'payment_mode' => 'online',
            'gateway' => 'razorpay',
            'status' => 'success',
            'paid_at' => now(),
            'idempotency_key' => 'advance:' . $appointment->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return $id;
    }
}
