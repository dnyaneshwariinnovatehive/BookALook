<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\Salon;
use App\Models\SalonCommissionRate;
use App\Models\SalonPayout;
use App\Models\ServiceProvider;
use App\Models\User;
use App\Services\PayoutService;
use App\Support\PayoutCycle;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Every booking is settled in exactly one payout, with the salon paid what
 * the platform actually holds for it:
 *
 *  - completed bookings: the online advance, commission on the full bill;
 *  - no-shows and late cancellations: whatever of the advance was not
 *    refunded, commission on that;
 *  - walk-ins: never commission;
 *  - refunds: only ever against the booking they belong to.
 */
class PayoutLedgerTest extends TestCase
{
    use DatabaseTransactions;

    private User $superadmin;
    private User $owner;
    private Salon $salon;
    private ServiceProvider $provider;
    private PayoutService $payouts;

    protected function setUp(): void
    {
        parent::setUp();

        $u = substr(bin2hex(random_bytes(6)), 0, 8);
        $this->superadmin = User::create(['id' => (string) Str::uuid(), 'role' => 'superadmin', 'name' => "SA {$u}", 'phone' => '3'.substr((string) crc32($u.'sa'), 0, 9), 'password_hash' => 'x', 'is_active' => true]);
        $this->owner = User::create(['id' => (string) Str::uuid(), 'role' => 'admin', 'name' => "Owner {$u}", 'phone' => '3'.substr((string) crc32($u.'ow'), 0, 9), 'password_hash' => 'x', 'is_active' => true]);
        $this->salon = Salon::create(['admin_id' => $this->owner->id, 'name' => "Ledger {$u}", 'slug' => "ledger-{$u}", 'address' => 'x', 'status' => 'active', 'submitted_by' => $this->owner->id]);
        $this->provider = ServiceProvider::create(['user_id' => $this->owner->id, 'salon_id' => $this->salon->id, 'is_active' => true]);
        $this->payouts = app(PayoutService::class);
    }

    // ── helpers ───────────────────────────────────────────────────────────

    private function commission(float $rate, string $from): void
    {
        $this->salon->forceFill(['commission_opt_in' => true, 'commission_percentage' => $rate])->save();
        SalonCommissionRate::create(['salon_id' => $this->salon->id, 'percentage' => $rate, 'effective_from' => $from]);
    }

    /** A booking; $paidOnline goes through the gateway as a platform payment. */
    private function booking(string $date, string $status, float $total, float $paidOnline = 0, string $source = 'online'): Appointment
    {
        $a = Appointment::create([
            'salon_id' => $this->salon->id,
            'appointed_provider_id' => $this->provider->id,
            'booking_source' => $source,
            'walk_in_customer_name' => $source === 'walk_in' ? 'Walk-in Wendy' : null,
            'appointment_date' => $date,
            'start_time' => '10:00:00',
            'end_time' => '10:30:00',
            'status' => $status,
            'total_amount' => $total,
            'advance_amount' => $paidOnline,
            'balance_amount' => $total - $paidOnline,
        ]);

        if ($paidOnline > 0) {
            DB::table('payments')->insert([
                'id' => (string) Str::uuid(), 'appointment_id' => $a->id, 'amount' => $paidOnline,
                'payment_type' => 'advance', 'payment_mode' => 'online', 'gateway' => 'razorpay',
                'status' => 'success', 'created_at' => now(), 'updated_at' => now(),
            ]);
        }

        return $a;
    }

    private function refund(Appointment $a, float $amount, string $status = 'processed', ?string $at = null): string
    {
        $id = (string) Str::uuid();
        DB::table('payment_refunds')->insert([
            'id' => $id,
            'payment_id' => DB::table('payments')->where('appointment_id', $a->id)->value('id'),
            'appointment_id' => $a->id, 'amount' => $amount, 'reason' => 'test', 'status' => $status,
            'created_at' => $at ?? now(), 'updated_at' => now(),
        ]);

        return $id;
    }

    private function week(string $day): SalonPayout
    {
        [$s, $e] = PayoutCycle::bounds(PayoutCycle::WEEKLY, Carbon::parse($day));

        return $this->payouts->calculate($this->salon->id, $s, $e, PayoutCycle::WEEKLY);
    }

    private function month(string $day): SalonPayout
    {
        [$s, $e] = PayoutCycle::bounds(PayoutCycle::MONTHLY, Carbon::parse($day));

        return $this->payouts->calculate($this->salon->id, $s, $e, PayoutCycle::MONTHLY);
    }

    // ── refunds ───────────────────────────────────────────────────────────

    public function test_a_refunded_cancellation_costs_the_salon_nothing(): void
    {
        $this->booking('2026-10-13', 'completed', 1000, 200);
        $cancelled = $this->booking('2026-10-14', 'cancelled', 500, 100);
        $this->refund($cancelled, 100);

        $p = $this->week('2026-10-13');

        $this->assertEquals(200.0, (float) $p->gross_amount);
        $this->assertEquals(0.0, (float) $p->refund_adjustment);
        $this->assertEquals(200.0, (float) $p->net_amount);
    }

    public function test_a_failed_refund_is_not_deducted(): void
    {
        $this->booking('2026-10-13', 'completed', 1000, 200);
        $noShow = $this->booking('2026-10-14', 'no_show', 500, 100);
        $this->refund($noShow, 100, 'failed');

        // The refund never happened, so the forfeited advance is the salon's.
        $this->assertEquals(300.0, (float) $this->week('2026-10-13')->net_amount);
    }

    // ── forfeited advances ────────────────────────────────────────────────

    public function test_no_show_and_late_cancellation_advances_go_to_the_salon(): void
    {
        $this->booking('2026-10-13', 'no_show', 800, 200);
        $late = $this->booking('2026-10-14', 'cancelled', 1000, 300);
        $this->refund($late, 100); // partly refundable: 200 forfeited

        $p = $this->week('2026-10-13');

        $this->assertEquals(400.0, (float) $p->gross_amount);
        $this->assertSame(2, (int) $p->appointments_count);
    }

    public function test_an_unpaid_cancelled_hold_is_not_money_to_settle(): void
    {
        // Abandoned at the payment screen: cancelled, advance figure set, never paid.
        Appointment::create([
            'salon_id' => $this->salon->id, 'appointed_provider_id' => $this->provider->id, 'booking_source' => 'online',
            'appointment_date' => '2026-10-13', 'start_time' => '10:00:00', 'end_time' => '10:30:00',
            'status' => 'cancelled', 'total_amount' => 900, 'advance_amount' => 300, 'balance_amount' => 600,
        ]);

        $this->assertEquals(0.0, (float) $this->week('2026-10-13')->net_amount);
    }

    public function test_commission_is_charged_on_a_forfeited_advance(): void
    {
        $this->commission(10, '2026-10-01');
        $this->booking('2026-10-14', 'no_show', 1000, 300);

        $p = $this->month('2026-10-01');

        $this->assertEquals(300.0, (float) $p->gross_amount);
        $this->assertEquals(30.0, (float) $p->commission_deducted);
        $this->assertEquals(270.0, (float) $p->net_amount);
    }

    // ── commission base ───────────────────────────────────────────────────

    public function test_walk_ins_are_commission_free(): void
    {
        $this->commission(10, '2026-10-01');
        $this->booking('2026-10-13', 'completed', 2000, 500);
        $this->booking('2026-10-14', 'completed', 5000, 0, 'walk_in');

        $p = $this->month('2026-10-01');

        $this->assertEquals(2000.0, (float) $p->appointment_revenue);
        $this->assertEquals(200.0, (float) $p->commission_deducted);
        $this->assertEquals(300.0, (float) $p->net_amount);
    }

    public function test_commission_is_on_the_full_bill_including_what_the_salon_added(): void
    {
        $this->commission(10, '2026-10-01');
        $a = $this->booking('2026-10-13', 'completed', 1000, 200);
        $a->forceFill(['final_billed_amount' => 1500])->save();

        $this->assertEquals(150.0, (float) $this->month('2026-10-01')->commission_deducted);
    }

    public function test_money_paid_at_the_counter_is_not_held_by_the_platform(): void
    {
        $a = $this->booking('2026-10-13', 'completed', 1000, 200);
        // Balance paid to the salon by UPI, recorded as "online" with no gateway.
        DB::table('payments')->insert([
            'id' => (string) Str::uuid(), 'appointment_id' => $a->id, 'amount' => 800,
            'payment_type' => 'balance', 'payment_mode' => 'online', 'status' => 'success',
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $this->assertEquals(200.0, (float) $this->week('2026-10-13')->gross_amount);
    }

    // ── one booking, one settlement ───────────────────────────────────────

    public function test_switching_to_commission_mid_month_never_pays_twice(): void
    {
        // Subscription for the first fortnight, paid out weekly.
        $this->booking('2026-10-06', 'completed', 1000, 200);
        $weekly = $this->week('2026-10-06');
        $this->payouts->markDistributed($this->payouts->approve($weekly, $this->superadmin), $this->superadmin, 'NEFT-1');

        // Joins the Commission Model on the 15th.
        $this->commission(10, '2026-10-15');
        $this->booking('2026-10-08', 'completed', 700, 100); // subscription week, never built weekly
        $this->booking('2026-10-20', 'completed', 2000, 400);

        $monthly = $this->month('2026-10-01');

        // The week already paid is not paid again; the unbuilt week is.
        $this->assertEquals(500.0, (float) $monthly->gross_amount);
        // Commission only from the day it joined.
        $this->assertEquals(200.0, (float) $monthly->commission_deducted);
        $this->assertEquals(300.0, (float) $monthly->net_amount);
    }

    public function test_a_booking_completed_after_its_week_was_paid_lands_in_the_next_payout(): void
    {
        $this->booking('2026-10-13', 'completed', 1000, 200);
        $late = $this->booking('2026-10-15', 'scheduled', 600, 150);

        $first = $this->week('2026-10-13');
        $this->payouts->markDistributed($this->payouts->approve($first, $this->superadmin), $this->superadmin, 'NEFT-1');
        $this->assertEquals(200.0, (float) $first->fresh()->net_amount);

        $late->forceFill(['status' => 'completed'])->save();

        $next = $this->week('2026-10-20');
        $this->assertEquals(150.0, (float) $next->net_amount);
        $this->assertEquals(200.0, (float) $first->fresh()->net_amount);
    }

    public function test_a_missed_weekly_run_is_picked_up_by_the_next_one(): void
    {
        $this->booking('2026-10-06', 'completed', 1000, 200);
        $this->booking('2026-10-14', 'completed', 1000, 300);

        // Only the later week is ever generated.
        $this->payouts->generateWeekly(Carbon::parse('2026-10-14'));

        $payout = SalonPayout::where('salon_id', $this->salon->id)->sole();
        $this->assertEquals(500.0, (float) $payout->net_amount);
    }

    public function test_recalculating_never_settles_a_booking_twice(): void
    {
        $this->booking('2026-10-13', 'completed', 1000, 200);

        $this->week('2026-10-13');
        $this->week('2026-10-13');
        $this->week('2026-10-20');

        $this->assertSame(1, DB::table('salon_payout_items')->where('kind', 'booking')
            ->whereIn('salon_payout_id', SalonPayout::where('salon_id', $this->salon->id)->pluck('id'))->count());
    }

    public function test_a_refund_after_settlement_comes_off_the_next_payout(): void
    {
        $a = $this->booking('2026-10-13', 'completed', 1000, 200);
        $first = $this->week('2026-10-13');
        $this->payouts->markDistributed($this->payouts->approve($first, $this->superadmin), $this->superadmin, 'NEFT-1');

        $this->refund($a, 50);
        $this->booking('2026-10-21', 'completed', 1000, 300);

        $next = $this->week('2026-10-20');
        $this->assertEquals(300.0, (float) $next->gross_amount);
        $this->assertEquals(50.0, (float) $next->refund_adjustment);
        $this->assertEquals(250.0, (float) $next->net_amount);

        // And only once.
        $this->assertEquals(250.0, (float) $this->week('2026-10-20')->net_amount);
    }

    // ── sign-off ──────────────────────────────────────────────────────────

    public function test_an_approved_payout_is_frozen(): void
    {
        $this->booking('2026-10-13', 'completed', 1000, 200);
        $approved = $this->payouts->approve($this->week('2026-10-13'), $this->superadmin);

        $this->booking('2026-10-14', 'completed', 1000, 300);

        $this->assertEquals(200.0, (float) $this->week('2026-10-13')->net_amount);
        // The newcomer waits for the next payout instead.
        $this->assertEquals(300.0, (float) $this->week('2026-10-20')->net_amount);
        $this->assertEquals(200.0, (float) $approved->fresh()->net_amount);
    }

    public function test_coins_cannot_be_spent_on_an_approved_payout(): void
    {
        $this->commission(10, '2026-10-01');
        $this->booking('2026-10-13', 'completed', 1000, 500);
        $approved = $this->payouts->approve($this->month('2026-10-01'), $this->superadmin);

        $this->actingAs($this->owner, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salon->id}/wallet/redeem-commission", [
                'payout_id' => $approved->id,
                'coins_to_redeem' => 10,
            ])
            ->assertStatus(422);

        $this->assertEquals(0.0, (float) $approved->fresh()->wallet_redeemed_amount);
    }

    public function test_a_salon_that_owes_is_shown_as_owing(): void
    {
        $this->commission(20, '2026-10-01');
        $this->booking('2026-10-13', 'completed', 5000, 200); // commission 1000 > 200 held

        $presented = $this->payouts->present($this->month('2026-10-01'));

        $this->assertEquals(-800.0, $presented['net_amount']);
        $this->assertSame('salon_owes', $presented['direction']);
        $this->assertEquals(800.0, $presented['amount_due']);
    }

    // ── who can touch payouts ─────────────────────────────────────────────

    public function test_only_superadmin_can_approve_or_distribute(): void
    {
        $this->booking('2026-10-13', 'completed', 1000, 200);
        $p = $this->week('2026-10-13');

        $this->actingAs($this->owner, 'sanctum')->postJson("/api/superadmin/payouts/{$p->id}/approve")->assertStatus(403);
        $this->actingAs($this->owner, 'sanctum')->postJson("/api/superadmin/payouts/{$p->id}/distribute")->assertStatus(403);
        $this->actingAs($this->owner, 'sanctum')->postJson('/api/superadmin/payouts/generate')->assertStatus(403);
        $this->assertSame(PayoutService::STATUS_PENDING, $p->fresh()->status);

        $this->actingAs($this->superadmin, 'sanctum')->postJson("/api/superadmin/payouts/{$p->id}/approve")->assertStatus(200);
    }

    public function test_salon_approval_and_directory_need_a_superadmin(): void
    {
        $this->app['auth']->forgetGuards();

        $this->getJson('/api/superadmin/salons/pending')->assertStatus(401);
        $this->postJson("/api/superadmin/salons/{$this->salon->id}/approve")->assertStatus(401);
        $this->getJson('/api/superadmin/salons')->assertStatus(401);
        $this->getJson('/api/superadmin/enquiries')->assertStatus(401);
        $this->postJson('/api/superadmin/collaborators', [])->assertStatus(401);

        $this->actingAs($this->owner, 'sanctum')->getJson('/api/superadmin/salons')->assertStatus(403);
    }
}
