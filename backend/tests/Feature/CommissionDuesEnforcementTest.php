<?php

namespace Tests\Feature;

use App\Models\Notification;
use App\Models\PayoutPaymentSubmission;
use App\Models\Salon;
use App\Models\SalonPayout;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Services\CommissionDuesService as Dues;
use App\Services\PayoutService;
use App\Services\SalonAccessService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * A Commission Model salon that owes BookALook: the ladder SuperAdmin set
 * (reminder → banner → full payment online → deduct → stop bookings → lock),
 * the per-salon controls, and everything lifting once it pays.
 *
 * Defaults: due 7 days after the month closes; banner on the due date; full
 * payment and deduction from day 3; bookings stop at day 10; lock at day 20.
 */
class CommissionDuesEnforcementTest extends TestCase
{
    use DatabaseTransactions;

    private User $superadmin;
    private Salon $salon;

    protected function setUp(): void
    {
        parent::setUp();

        $u = Str::random(6);
        $this->superadmin = $this->user('superadmin', $u);
        $owner = $this->user('admin', $u);
        $this->salon = Salon::create([
            'admin_id' => $owner->id, 'name' => "Owes {$u}", 'slug' => "owes-{$u}", 'address' => 'x',
            'status' => 'active', 'submitted_by' => $owner->id,
        ]);
        $this->salon->forceFill(['commission_opt_in' => true, 'commission_percentage' => 10])->save();

        $plan = SubscriptionPlan::create(['name' => 'Commission ' . $u, 'price' => 0, 'validity_days' => 30, 'is_active' => true]);
        SalonSubscription::create([
            'salon_id' => $this->salon->id, 'plan_id' => $plan->id, 'billing_type' => 'commission',
            'plan_price_snapshot' => 0, 'start_date' => '2026-08-01', 'end_date' => '2099-12-31', 'status' => 'active',
        ]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function user(string $role, string $u): User
    {
        return User::create([
            'id' => (string) Str::uuid(), 'role' => $role, 'name' => ucfirst($role) . " {$u}",
            'phone' => '4' . random_int(100000000, 999999999), 'password_hash' => 'x', 'is_active' => true,
        ]);
    }

    /** September closes on the 30th, so its dues fall due on 7 October. */
    private function owes(float $amount, string $start = '2026-09-01', string $end = '2026-09-30'): SalonPayout
    {
        return SalonPayout::create([
            'salon_id' => $this->salon->id, 'cycle_type' => 'monthly', 'billing_type' => 'commission',
            'cycle_start_date' => $start, 'cycle_end_date' => $end, 'status' => 'pending',
            'gross_amount' => 0, 'appointment_revenue' => 0, 'appointments_count' => 0,
            'commission_deducted' => $amount, 'refund_adjustment' => 0, 'wallet_redeemed_amount' => 0,
            'net_amount' => -$amount,
        ]);
    }

    private function on(string $date): array
    {
        Carbon::setTestNow($date . ' 12:00:00');

        return app(Dues::class)->state($this->salon->fresh());
    }

    public function test_the_ladder_climbs_with_the_days_overdue(): void
    {
        $this->owes(1000);

        $this->assertSame([], $this->on('2026-10-01')['actions'], 'nothing before the reminder window');

        $s = $this->on('2026-10-05');
        $this->assertSame([Dues::STEP_REMINDER], $s['actions']);
        $this->assertSame('2026-10-07', $s['due_date']);
        $this->assertSame(Dues::STEP_BANNER, $s['next']['step']);

        $this->assertSame([Dues::STEP_REMINDER, Dues::STEP_BANNER], $this->on('2026-10-07')['actions']);

        $s = $this->on('2026-10-10');
        $this->assertContains(Dues::STEP_FORCE_ADVANCE, $s['actions']);
        $this->assertContains(Dues::STEP_DEDUCT, $s['actions']);

        $access = app(SalonAccessService::class);
        $status = $access->status($this->salon->fresh());
        $this->assertTrue(SalonAccessService::takesBookings($status));

        $this->on('2026-10-17');
        $status = $access->status($this->salon->fresh());
        $this->assertTrue($status['is_active'], 'the Partner App still works');
        $this->assertFalse(SalonAccessService::takesBookings($status), 'customers cannot book');

        $this->on('2026-10-27');
        $status = $access->status($this->salon->fresh());
        $this->assertFalse($status['is_active']);
        $this->assertSame(SalonAccessService::REASON_COMMISSION_UNSETTLED, $status['reason']);
    }

    public function test_small_dues_and_payments_under_review_are_left_alone(): void
    {
        $this->owes(150);
        $s = $this->on('2026-11-30');
        $this->assertTrue($s['below_minimum']);
        $this->assertSame([], $s['actions']);

        $big = $this->owes(900, '2026-08-01', '2026-08-31');
        PayoutPaymentSubmission::create([
            'salon_payout_id' => $big->id, 'salon_id' => $this->salon->id, 'amount' => 900,
            'status' => PayoutPaymentSubmission::STATUS_PENDING, 'screenshot_url' => 'x.png',
        ]);
        $s = $this->on('2026-11-30');
        $this->assertSame(1, $s['under_review']);
        $this->assertEquals(150, $s['owed'], 'the payout being verified is not chased');
    }

    public function test_superadmin_can_extend_pause_and_force_a_step(): void
    {
        $this->owes(1000);
        Carbon::setTestNow('2026-10-27 12:00:00'); // day 20: locked

        $as = $this->actingAs($this->superadmin, 'sanctum');
        $id = $this->salon->id;

        $as->postJson("/api/superadmin/commission-dues/{$id}/extend", ['until' => '2026-10-25', 'reason' => 'x'])
            ->assertStatus(422); // must be in the future

        $as->postJson("/api/superadmin/commission-dues/{$id}/extend", ['until' => '2026-11-05', 'reason' => 'Owner unwell'])
            ->assertOk()
            ->assertJsonPath('row.state.due_date', '2026-11-05');
        $this->assertTrue(app(SalonAccessService::class)->status($this->salon->fresh())['is_active']);

        $as->postJson("/api/superadmin/commission-dues/{$id}/stage", ['stage' => Dues::STEP_STOP_BOOKINGS, 'reason' => 'Ignoring calls'])
            ->assertOk();
        $this->assertSame(Dues::STEP_STOP_BOOKINGS, $this->on('2026-10-27')['stage']);

        $as->postJson("/api/superadmin/commission-dues/{$id}/pause", ['paused' => true, 'reason' => 'Talking to them'])
            ->assertOk();
        $this->assertSame([], $this->on('2026-10-27')['actions']);

        $list = $as->getJson('/api/superadmin/commission-dues')->assertOk()->json();
        $row = collect($list['data'])->firstWhere('salon.id', $id);
        $this->assertTrue($row['state']['paused']);
        $this->assertEquals(1000, $row['state']['owed']);
    }

    public function test_recording_a_payment_lifts_everything(): void
    {
        $this->owes(1000);
        Carbon::setTestNow('2026-10-27 12:00:00');
        $this->assertFalse(app(SalonAccessService::class)->status($this->salon->fresh())['is_active']);

        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson("/api/superadmin/commission-dues/{$this->salon->id}/record-payment", ['reference' => 'UPI-998877'])
            ->assertOk();

        $this->assertTrue(app(SalonAccessService::class)->status($this->salon->fresh())['is_active']);
        $this->assertFalse(app(Dues::class)->state($this->salon->fresh())['applies']);
        $this->assertSame('UPI-998877', SalonPayout::where('salon_id', $this->salon->id)->first()->distribution_reference);
    }

    public function test_money_owed_to_the_salon_clears_its_dues_once_deduction_starts(): void
    {
        $owed = $this->owes(400);
        $theirs = SalonPayout::create([
            'salon_id' => $this->salon->id, 'cycle_type' => 'monthly', 'billing_type' => 'commission',
            'cycle_start_date' => '2026-10-01', 'cycle_end_date' => '2026-10-31', 'status' => 'approved',
            'gross_amount' => 1500, 'appointment_revenue' => 1500, 'appointments_count' => 3,
            'commission_deducted' => 150, 'refund_adjustment' => 0, 'wallet_redeemed_amount' => 0,
            'net_amount' => 1350,
        ]);

        Carbon::setTestNow('2026-11-02 12:00:00'); // well past day 3
        $paid = app(PayoutService::class)->markDistributed($theirs, $this->superadmin, 'NEFT-1');

        $this->assertEquals(950, $paid->net_amount, '1350 owed to the salon less its 400 dues');
        $this->assertEquals(-400, $paid->dues_adjustment);
        $owed->refresh();
        $this->assertSame('distributed', $owed->status);
        $this->assertEquals(0, $owed->net_amount);
        $this->assertStringContainsString('Recovered from', $owed->distribution_reference);
    }

    public function test_no_deduction_before_that_step(): void
    {
        $owed = $this->owes(400);
        $theirs = SalonPayout::create([
            'salon_id' => $this->salon->id, 'cycle_type' => 'weekly', 'billing_type' => 'commission',
            'cycle_start_date' => '2026-09-28', 'cycle_end_date' => '2026-10-04', 'status' => 'approved',
            'gross_amount' => 1000, 'appointment_revenue' => 1000, 'appointments_count' => 2,
            'commission_deducted' => 100, 'refund_adjustment' => 0, 'wallet_redeemed_amount' => 0,
            'net_amount' => 900,
        ]);

        Carbon::setTestNow('2026-10-08 12:00:00'); // day 1: banner only
        $paid = app(PayoutService::class)->markDistributed($theirs, $this->superadmin, 'NEFT-2');

        $this->assertEquals(900, $paid->net_amount);
        $this->assertSame('pending', $owed->fresh()->status);
    }

    public function test_the_daily_pass_tells_the_owner_once_per_new_step(): void
    {
        $this->owes(1000);
        Carbon::setTestNow('2026-10-17 12:00:00'); // day 10

        $this->artisan('app:enforce-commission-dues')->assertSuccessful();
        $this->artisan('app:enforce-commission-dues')->assertSuccessful();

        $notices = Notification::where('user_id', $this->salon->admin_id)
            ->where('title', 'like', Dues::LABELS[Dues::STEP_STOP_BOOKINGS] . '%')
            ->count();
        $this->assertSame(1, $notices);
        $this->assertSame(Dues::STEP_STOP_BOOKINGS, $this->salon->fresh()->dues_notified_stage);
    }

    public function test_switching_a_step_off_in_policy_skips_it(): void
    {
        $this->owes(1000);
        \App\Models\PlatformPolicySetting::updateOrCreate(
            ['setting_key' => 'commission_dues_full_lock_enabled'],
            ['setting_value' => '0', 'data_type' => 'boolean', 'description' => 'x']
        );

        Carbon::setTestNow('2026-12-31 12:00:00');
        $status = app(SalonAccessService::class)->status($this->salon->fresh());
        $this->assertTrue($status['is_active']);
        $this->assertTrue($status['bookings_paused']);
    }
}
