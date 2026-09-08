<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\AppointmentService as AppointmentLine;
use App\Models\AppointmentServiceAddition;
use App\Models\ProviderLeave;
use App\Models\ProviderWorkingHour;
use App\Models\SalaryPayout;
use App\Models\Salon;
use App\Models\SalonPayout;
use App\Models\SalonSubscription;
use App\Models\ServiceProvider;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Services\PayoutService;
use App\Services\PayrollService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use App\Models\SalonCommissionRate;
use App\Support\BillingModel;
use App\Support\PayoutCycle;
use Tests\TestCase;

/**
 * Settlement with the salon, and monthly pay for its staff.
 *
 * Runs in a transaction so it can use the development database without
 * leaving anything behind.
 */
class PayoutAndPayrollTest extends TestCase
{
    use DatabaseTransactions;

    // ------------------------------------------------- payout & distribution

    public function test_commission_comes_off_the_advances_the_platform_holds(): void
    {
        [$salon, $superAdmin, $provider] = $this->fixture();
        $this->givenSubscription($salon, BillingModel::COMMISSION, 10.0);

        // The Commission Model settles a month at a time, on the 1st.
        [$start, $end] = $this->thisMonth();

        // Two completed appointments: ₹5,000 billed, ₹1,500 taken as advance.
        $this->givenCompleted($salon, $provider, total: 2000, advance: 600, on: $start);
        $this->givenCompleted($salon, $provider, total: 3000, advance: 900, on: $start);

        $payout = app(PayoutService::class)->calculate($salon->id, $start, $end);

        // Commission is charged on everything billed...
        $this->assertEquals(5000.0, (float) $payout->appointment_revenue);
        $this->assertEquals(500.0, (float) $payout->commission_deducted);
        // ...but only the advances are the platform's to hand over.
        $this->assertEquals(1500.0, (float) $payout->gross_amount);
        $this->assertEquals(1000.0, (float) $payout->net_amount);
        $this->assertSame(BillingModel::COMMISSION, $payout->billing_type);
        $this->assertSame(PayoutCycle::MONTHLY, $payout->cycle_type);
        $this->assertSame(2, (int) $payout->appointments_count);
    }

    public function test_a_subscription_plan_salon_has_nothing_deducted(): void
    {
        [$salon, , $provider] = $this->fixture();
        $this->givenSubscription($salon, BillingModel::SUBSCRIPTION);

        [$weekStart, $weekEnd] = $this->thisWeek();
        $this->givenCompleted($salon, $provider, total: 4000, advance: 1000, on: $weekStart);

        $payout = app(PayoutService::class)->calculate($salon->id, $weekStart, $weekEnd);

        $this->assertEquals(0.0, (float) $payout->commission_deducted);
        $this->assertEquals(1000.0, (float) $payout->net_amount);
    }

    public function test_superadmin_approves_then_distributes_and_the_record_is_frozen(): void
    {
        [$salon, $superAdmin, $provider] = $this->fixture();
        $this->givenSubscription($salon, BillingModel::COMMISSION, 20.0);

        [$start, $end] = $this->thisMonth();
        $this->givenCompleted($salon, $provider, total: 1000, advance: 400, on: $start);

        app(PayoutService::class)->calculate($salon->id, $start, $end);

        $listed = $this->actingAs($superAdmin, 'sanctum')
            ->getJson('/api/superadmin/payouts?cycle_type=monthly&cycle_start=' . $start->toDateString())
            ->assertStatus(200)
            ->json();

        $row = collect($listed['payouts'])->firstWhere('salon_id', $salon->id);
        $this->assertNotNull($row);
        $this->assertEquals(200.0, $row['commission_deducted']);
        $this->assertEquals(200.0, $row['net_amount']);

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$row['id']}/approve")
            ->assertStatus(200)
            ->assertJsonPath('payout.status', PayoutService::STATUS_APPROVED);

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$row['id']}/distribute", [
                'distribution_reference' => 'NEFT-12345',
            ])
            ->assertStatus(200)
            ->assertJsonPath('payout.status', PayoutService::STATUS_DISTRIBUTED)
            ->assertJsonPath('payout.distribution_reference', 'NEFT-12345');

        // Distributing twice would pay twice.
        $this->actingAs($superAdmin, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$row['id']}/distribute")
            ->assertStatus(422);

        // A late recalculation must not rewrite money that has already moved.
        $this->givenCompleted($salon, $provider, total: 9999, advance: 5000, on: $start);
        $again = app(PayoutService::class)->calculate($salon->id, $start, $end);
        $this->assertEquals(200.0, (float) $again->net_amount);
    }

    public function test_the_salon_can_see_the_commission_taken_off_its_own_payout(): void
    {
        [$salon, , $provider] = $this->fixture();
        $admin = User::find($salon->admin_id);
        $this->givenSubscription($salon, BillingModel::COMMISSION, 15.0);

        [$start, $end] = $this->thisMonth();
        $this->givenCompleted($salon, $provider, total: 2000, advance: 800, on: $start);
        app(PayoutService::class)->calculate($salon->id, $start, $end);

        $body = $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/payouts")
            ->assertStatus(200)
            ->json();

        $row = collect($body['payouts'])->firstWhere('cycle_start_date', $start->toDateString());
        $this->assertNotNull($row);
        $this->assertEquals(300.0, $row['commission_deducted']);
        $this->assertEquals(15.0, $row['commission_percentage']);
        $this->assertEquals(500.0, $row['net_amount']);
    }

    // ---------------------------------------------------------------- payroll

    public function test_pay_is_base_minus_unpaid_leave_plus_commission(): void
    {
        [$salon, , $provider] = $this->fixture();
        $month = Carbon::today()->startOfMonth();

        $provider->forceFill(['base_salary' => 30000, 'commission_percentage' => 20])->save();
        // Rostered every day, so the divisor is the month's length.
        $this->givenRoster($provider, offDays: []);

        // Two unpaid days and one paid day off.
        $this->givenLeave($provider, $month->copy()->addDays(2), ProviderLeave::TYPE_UNPAID);
        $this->givenLeave($provider, $month->copy()->addDays(3), ProviderLeave::TYPE_UNPAID);
        $this->givenLeave($provider, $month->copy()->addDays(4), ProviderLeave::TYPE_PAID);

        // ₹2,000 of commission across a booked line and a mid-appointment extra.
        $appointment = $this->givenCompleted($salon, $provider, total: 5000, advance: 0, on: $month->copy()->addDays(1));
        $this->givenCommissionLine($appointment, $provider, charged: 5000, commission: 1000);
        $this->givenCommissionAddition($appointment, $provider, charged: 5000, commission: 1000);

        $payslip = app(PayrollService::class)->build($provider->fresh(), $month);

        $days = $month->daysInMonth;
        $dailyRate = round(30000 / $days, 2);

        $this->assertSame($days, (int) $payslip->working_days_in_month);
        $this->assertEquals($dailyRate, (float) $payslip->daily_rate);
        $this->assertEquals(2.0, (float) $payslip->unpaid_leave_days);
        // Paid leave is time off that costs nothing.
        $this->assertEquals(1.0, (float) $payslip->paid_leave_days);
        $this->assertEquals(round($dailyRate * 2, 2), (float) $payslip->unpaid_leave_deduction);
        $this->assertEquals(2000.0, (float) $payslip->commission_earned);
        $this->assertEquals(
            round(30000 - ($dailyRate * 2) + 2000, 2),
            (float) $payslip->total_payable
        );
    }

    public function test_the_divisor_follows_the_providers_own_roster(): void
    {
        [, , $provider] = $this->fixture();
        $month = Carbon::today()->startOfMonth();

        $provider->forceFill(['base_salary' => 26000])->save();

        // One day off a week.
        $this->givenRoster($provider, offDays: [0]);
        $sixDay = app(PayrollService::class)->workingDaysInMonth($provider->id, $month);

        // Two days off a week — fewer working days, so each is worth more.
        $this->givenRoster($provider, offDays: [0, 6]);
        $fiveDay = app(PayrollService::class)->workingDaysInMonth($provider->id, $month);

        $this->assertGreaterThan($fiveDay, $sixDay);
        $this->assertGreaterThan(26000 / $sixDay, 26000 / $fiveDay);
    }

    public function test_commission_follows_the_provider_who_delivered_each_line(): void
    {
        [$salon, , $provider, $other] = $this->fixture(needsSecondProvider: true);
        $month = Carbon::today()->startOfMonth();

        $appointment = $this->givenCompleted($salon, $provider, total: 3000, advance: 0, on: $month->copy()->addDay());

        // The booked service was done by the appointment's provider...
        $this->givenCommissionLine($appointment, $provider, charged: 2000, commission: 400);
        // ...and a colleague stepped in for the extra.
        $this->givenCommissionAddition($appointment, $other, charged: 1000, commission: 250);

        $payroll = app(PayrollService::class);

        $this->assertEquals(400.0, $payroll->commissionEarned($provider->id, $month));
        $this->assertEquals(250.0, $payroll->commissionEarned($other->id, $month));

        // The breakdown says which line each amount came from.
        $lines = $payroll->commissionBreakdown($other->id, $month);
        $this->assertCount(1, $lines);
        $this->assertTrue($lines[0]['added_mid_appointment']);
        $this->assertEquals(1000.0, $lines[0]['charged']);
    }

    public function test_admin_marks_a_salary_paid_and_the_figures_freeze(): void
    {
        [$salon, , $provider] = $this->fixture();
        $admin = User::find($salon->admin_id);
        $month = Carbon::today()->startOfMonth();

        $provider->forceFill(['base_salary' => 20000, 'commission_percentage' => 10])->save();
        $this->givenRoster($provider, offDays: []);

        $listed = $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/payroll?month=" . $month->format('Y-m'))
            ->assertStatus(200)
            ->json();

        $payslip = collect($listed['payslips'])->firstWhere('provider_id', $provider->id);
        $this->assertNotNull($payslip);
        $this->assertSame(SalaryPayout::STATUS_PENDING, $payslip['status']);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/payroll/{$payslip['id']}/mark-paid", [
                'payment_reference' => 'UPI-9911',
            ])
            ->assertStatus(200)
            ->assertJsonPath('payslip.status', SalaryPayout::STATUS_PAID);

        // A raise afterwards must not rewrite a payslip that has been settled.
        $provider->forceFill(['base_salary' => 99000])->save();
        $rebuilt = app(PayrollService::class)->build($provider->fresh(), $month);
        $this->assertEquals(20000.0, (float) $rebuilt->base_salary_snapshot);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/payroll/{$payslip['id']}/mark-unpaid")
            ->assertStatus(200)
            ->assertJsonPath('payslip.status', SalaryPayout::STATUS_PENDING);
    }

    public function test_a_provider_sees_their_own_payslip_but_not_anyone_elses(): void
    {
        [$salon, , $provider, $other] = $this->fixture(needsSecondProvider: true);
        $month = Carbon::today()->startOfMonth();

        $provider->forceFill(['base_salary' => 18000])->save();
        $this->givenRoster($provider, offDays: []);

        $body = $this->actingAs($provider->user, 'sanctum')
            ->getJson('/api/partner/me/payroll?month=' . $month->format('Y-m'))
            ->assertStatus(200)
            ->json();

        $this->assertEquals(18000.0, $body['payslip']['base_salary']);
        $this->assertArrayHasKey('commission_lines', $body['payslip']);
        $this->assertArrayHasKey('history', $body);

        // Their colleague's payslip is not theirs to read.
        $this->actingAs($provider->user, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/payroll/staff/{$other->id}")
            ->assertStatus(403);

        // Nor is the whole salon's payroll.
        $this->actingAs($provider->user, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/payroll")
            ->assertStatus(403);
    }

    public function test_leave_is_auto_approved_only_when_that_staff_member_is_set_to(): void
    {
        [$salon, , $provider] = $this->fixture();

        $provider->forceFill(['auto_approve_leave' => false])->save();

        $this->actingAs($provider->user, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/leaves", [
                'leave_date' => Carbon::today()->addDays(3)->toDateString(),
                'leave_type' => 'unpaid',
                'reason' => 'Family function',
            ])
            ->assertStatus(201)
            ->assertJsonPath('auto_approved', false)
            ->assertJsonPath('leave.status', ProviderLeave::STATUS_PENDING);

        $provider->forceFill(['auto_approve_leave' => true])->save();

        $this->actingAs($provider->user, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/leaves", [
                'leave_date' => Carbon::today()->addDays(4)->toDateString(),
                'leave_type' => 'paid',
            ])
            ->assertStatus(201)
            ->assertJsonPath('auto_approved', true)
            ->assertJsonPath('leave.status', ProviderLeave::STATUS_APPROVED);

        // Double-booking the same day is refused.
        $this->actingAs($provider->user, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/leaves", [
                'leave_date' => Carbon::today()->addDays(4)->toDateString(),
                'leave_type' => 'unpaid',
            ])
            ->assertStatus(422);
    }

    public function test_only_approved_unpaid_leave_is_deducted(): void
    {
        [, , $provider] = $this->fixture();
        $month = Carbon::today()->startOfMonth();

        $provider->forceFill(['base_salary' => 30000])->save();
        $this->givenRoster($provider, offDays: []);

        // Requested but not approved yet, so it costs nothing.
        $this->givenLeave($provider, $month->copy()->addDays(5), ProviderLeave::TYPE_UNPAID, ProviderLeave::STATUS_PENDING);
        // Half a day approved.
        $this->givenLeave($provider, $month->copy()->addDays(6), ProviderLeave::TYPE_UNPAID, fullDay: false);

        $payslip = app(PayrollService::class)->build($provider->fresh(), $month);

        $this->assertEquals(0.5, (float) $payslip->unpaid_leave_days);
        $this->assertEquals(
            round(round(30000 / $month->daysInMonth, 2) * 0.5, 2),
            (float) $payslip->unpaid_leave_deduction
        );
    }

    // ------------------------------------------------------------- fixtures

    /**
     * A salon of its own for each test.
     *
     * The development database already holds real appointments and commission,
     * so sharing a salon would make every total a moving target. Building a
     * fresh one keeps the assertions absolute and readable.
     *
     * @return array{0: Salon, 1: User, 2: ServiceProvider, 3: ?ServiceProvider}
     */
    private function fixture(bool $needsSecondProvider = false): array
    {
        $superAdmin = User::where('role', 'superadmin')->first() ?? User::where('role', 'admin')->first();

        if (! $superAdmin) {
            $this->markTestSkipped('needs an elevated account');
        }

        $unique = substr(bin2hex(random_bytes(6)), 0, 10);

        $admin = User::create([
            'name' => "Payroll Admin {$unique}",
            'phone' => '9' . substr((string) crc32($unique), 0, 9),
            'password_hash' => 'x',
            'role' => 'admin',
            'is_active' => true,
        ]);

        $salon = Salon::create([
            'admin_id' => $admin->id,
            'name' => "Payroll Salon {$unique}",
            'slug' => "payroll-salon-{$unique}",
            'address' => 'Test address',
            'submitted_by' => $admin->id,
            'status' => 'active',
        ]);

        // Payroll sits behind the subscription gate, so the salon has to be
        // trading for these tests to reach it.
        $this->givenSubscription($salon, BillingModel::SUBSCRIPTION);

        $provider = $this->givenProvider($salon, "Staff A {$unique}");
        $other = $needsSecondProvider ? $this->givenProvider($salon, "Staff B {$unique}") : null;

        // The salon needs something to sell for commission lines to exist.
        $this->givenService($salon);

        return [$salon, $superAdmin, $provider, $other];
    }

    private function givenProvider(Salon $salon, string $name): ServiceProvider
    {
        $user = User::create([
            'name' => $name,
            'phone' => '8' . substr((string) crc32($name . microtime()), 0, 9),
            'password_hash' => 'x',
            'role' => 'service_provider',
            'is_active' => true,
        ]);

        return ServiceProvider::create([
            'user_id' => $user->id,
            'salon_id' => $salon->id,
            'base_salary' => 0,
            'commission_percentage' => 0,
            'auto_approve_leave' => false,
            'is_active' => true,
            'joined_at' => Carbon::today()->subYear(),
        ])->load('user');
    }

    private function givenService(Salon $salon): \App\Models\Service
    {
        $template = \App\Models\ServiceTemplate::first();

        if (! $template) {
            $this->markTestSkipped('needs a service template in the catalogue');
        }

        return \App\Models\Service::create([
            'salon_id' => $salon->id,
            'template_id' => $template->id,
            'price' => 1000,
            'is_active' => true,
        ]);
    }

    /** @return array{0: Carbon, 1: Carbon} */
    private function thisWeek(): array
    {
        $start = Carbon::today()->startOfWeek();

        return [$start, $start->copy()->endOfWeek()];
    }

    /** The cycle a Commission Model salon settles on. @return array{0: Carbon, 1: Carbon} */
    private function thisMonth(): array
    {
        $start = Carbon::today()->startOfMonth();

        return [$start, $start->copy()->endOfMonth()];
    }

    /**
     * Put the salon on one of the two arrangements.
     *
     * The salon row is the source of truth for which model it is on and what
     * it is charged — the subscription row is replaced on every renewal, which
     * is exactly why the rate no longer lives there.
     */
    private function givenSubscription(Salon $salon, string $billingType, ?float $rate = null): void
    {
        SalonSubscription::where('salon_id', $salon->id)->update(['status' => 'cancelled']);

        $plan = SubscriptionPlan::first();

        if (! $plan) {
            $this->markTestSkipped('needs a subscription plan');
        }

        $isCommission = BillingModel::isCommission($billingType);

        $salon->forceFill([
            'commission_opt_in' => $isCommission,
            'commission_percentage' => $isCommission ? $rate : null,
            'commission_rate_effective_from' => $isCommission ? Carbon::today()->subDay() : null,
        ])->save();

        if ($isCommission) {
            SalonCommissionRate::where('salon_id', $salon->id)->update(['effective_to' => Carbon::yesterday()]);
            SalonCommissionRate::create([
                'salon_id' => $salon->id,
                'percentage' => $rate ?? 0,
                'effective_from' => Carbon::today()->subDay(),
            ]);
        }

        SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'billing_type' => $billingType,
            'commission_percentage' => $rate,
            'plan_price_snapshot' => $plan->price,
            'start_date' => Carbon::today()->subDays(1),
            'end_date' => Carbon::today()->addDays(30),
            'status' => 'active',
        ]);
    }

    private function givenCompleted(
        Salon $salon,
        ServiceProvider $provider,
        float $total,
        float $advance,
        Carbon $on
    ): Appointment {
        return Appointment::create([
            'salon_id' => $salon->id,
            'appointed_provider_id' => $provider->id,
            'serving_provider_id' => $provider->id,
            'booking_source' => 'online',
            'appointment_date' => $on->toDateString(),
            'start_time' => '10:00:00',
            'end_time' => '10:30:00',
            'status' => 'completed',
            'payment_option' => 'advance_only',
            'total_amount' => $total,
            'advance_amount' => $advance,
            'balance_amount' => $total - $advance,
            'completed_at' => now(),
        ]);
    }

    private function givenCommissionLine(
        Appointment $appointment,
        ServiceProvider $provider,
        float $charged,
        float $commission
    ): void {
        $service = \App\Models\Service::where('salon_id', $appointment->salon_id)->firstOrFail();

        AppointmentLine::create([
            'appointment_id' => $appointment->id,
            'service_id' => $service->id,
            'serving_provider_id' => $provider->id,
            'price_at_booking' => $charged,
            'original_service_price' => $service->price,
            'duration_minutes_at_booking' => 30,
            'commission_percentage_snapshot' => $charged > 0 ? round($commission / $charged * 100, 2) : 0,
            'commission_amount' => $commission,
            'line_status' => 'completed',
        ]);
    }

    private function givenCommissionAddition(
        Appointment $appointment,
        ServiceProvider $provider,
        float $charged,
        float $commission
    ): void {
        $service = \App\Models\Service::where('salon_id', $appointment->salon_id)->firstOrFail();

        AppointmentServiceAddition::create([
            'appointment_id' => $appointment->id,
            'service_id' => $service->id,
            'provider_id' => $provider->id,
            'added_by' => $provider->user_id,
            'price_at_addition' => $charged,
            'duration_minutes_at_addition' => 30,
            'commission_percentage_snapshot' => $charged > 0 ? round($commission / $charged * 100, 2) : 0,
            'commission_amount' => $commission,
            'status' => 'active',
            'added_at' => now(),
        ]);
    }

    /** @param array<int, int> $offDays */
    private function givenRoster(ServiceProvider $provider, array $offDays): void
    {
        ProviderWorkingHour::where('provider_id', $provider->id)->delete();

        for ($day = 0; $day < 7; $day++) {
            $off = in_array($day, $offDays, true);

            ProviderWorkingHour::create([
                'provider_id' => $provider->id,
                'day_of_week' => $day,
                'is_weekly_off' => $off,
                'shift_start' => $off ? null : '09:00:00',
                'shift_end' => $off ? null : '18:00:00',
            ]);
        }
    }

    private function givenLeave(
        ServiceProvider $provider,
        Carbon $date,
        string $type,
        string $status = ProviderLeave::STATUS_APPROVED,
        bool $fullDay = true
    ): void {
        ProviderLeave::create([
            'provider_id' => $provider->id,
            'leave_date' => $date->toDateString(),
            'leave_type' => $type,
            'is_full_day' => $fullDay,
            'start_time' => $fullDay ? null : '10:00:00',
            'end_time' => $fullDay ? null : '14:00:00',
            'status' => $status,
        ]);
    }
}
