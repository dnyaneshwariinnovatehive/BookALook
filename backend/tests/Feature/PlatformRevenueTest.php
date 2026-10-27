<?php

namespace Tests\Feature;

use App\Models\Salon;
use App\Models\SalonPayout;
use App\Models\SubscriptionPlan;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * BookALook's own revenue: approved plan payments (cash, after coins) and
 * settled commission; open commission reported apart as pending.
 */
class PlatformRevenueTest extends TestCase
{
    use DatabaseTransactions;

    private function user(string $role): User
    {
        return User::create([
            'id' => (string) Str::uuid(), 'name' => ucfirst($role), 'phone' => '9' . random_int(100000000, 999999999),
            'password_hash' => 'x', 'role' => $role, 'is_active' => true,
        ]);
    }

    private function salon(string $name): Salon
    {
        $owner = $this->user('admin');

        return Salon::create([
            'id' => (string) Str::uuid(), 'admin_id' => $owner->id, 'name' => $name,
            'slug' => Str::slug($name) . '-' . Str::random(6), 'address' => 'x', 'status' => 'active', 'submitted_by' => $owner->id,
        ]);
    }

    private function planPayment(Salon $salon, SubscriptionPlan $plan, string $status, float $cash, float $coins, string $at): void
    {
        DB::table('subscription_payment_requests')->insert([
            'salon_id' => $salon->id, 'subscription_plan_id' => $plan->id, 'billing_type' => 'subscription',
            'screenshot_url' => 'x.png', 'status' => $status, 'coins_to_redeem' => 0,
            'coin_discount_inr' => $coins, 'amount_payable_inr' => $cash,
            'created_at' => $at, 'updated_at' => $at,
        ]);
    }

    private function payout(Salon $salon, string $status, float $commission, float $coins, ?string $distributedAt): void
    {
        SalonPayout::create([
            'salon_id' => $salon->id, 'cycle_type' => 'monthly', 'billing_type' => 'commission',
            'cycle_start_date' => '2026-09-01', 'cycle_end_date' => '2026-09-30', 'status' => $status,
            'gross_amount' => 0, 'appointment_revenue' => 0, 'appointments_count' => 0,
            'commission_deducted' => $commission, 'refund_adjustment' => 0, 'wallet_redeemed_amount' => $coins,
            'net_amount' => -($commission - $coins), 'distributed_at' => $distributedAt,
        ]);
    }

    public function test_revenue_counts_plan_cash_and_settled_commission_only(): void
    {
        Carbon::setTestNow('2026-10-26 12:00:00');
        $plan = SubscriptionPlan::create(['name' => 'Growth ' . Str::random(4), 'price' => 999, 'validity_days' => 30, 'is_active' => true]);
        $a = $this->salon('Rev A');
        $b = $this->salon('Rev B');

        $this->planPayment($a, $plan, 'approved', 899, 100, '2026-10-20 10:00:00');
        $this->planPayment($b, $plan, 'approved', 999, 0, '2026-10-21 10:00:00');
        $this->planPayment($b, $plan, 'pending', 999, 0, '2026-10-22 10:00:00');   // not yet revenue
        $this->planPayment($a, $plan, 'approved', 999, 0, '2026-08-01 10:00:00');  // outside the window

        $this->payout($a, 'distributed', 500, 50, '2026-10-02 10:00:00');          // 450 cash, 50 coins
        $this->payout($b, 'pending', 300, 0, null);                                 // pending

        $json = $this->actingAs($this->user('superadmin'), 'sanctum')
            ->getJson('/api/superadmin/reports/platform-revenue?from=2026-10-01&to=2026-10-26&granularity=weekly')
            ->assertOk()
            ->json();

        $t = $json['totals'];
        $this->assertEquals(1898, $t['subscriptions']);
        $this->assertSame(2, $t['subscription_payments']);
        $this->assertEquals(450, $t['commission']);
        $this->assertEquals(2348, $t['total']);
        $this->assertEquals(150, $t['coins_given']);
        $this->assertSame(2, $t['paying_salons']);

        $this->assertGreaterThanOrEqual(300, $json['pending_commission']['amount']);
        $this->assertEquals(2348, array_sum(array_column($json['trend'], 'total')));
        $this->assertContains('Commission', array_column($json['by_plan'], 'name'));
        $this->assertSame('Rev A', $json['top_salons'][0]['name']);
        $this->assertGreaterThanOrEqual(2348 + 999, $json['all_time']['total']);
    }

    public function test_only_superadmin_sees_platform_revenue(): void
    {
        $this->actingAs($this->user('admin'), 'sanctum')
            ->getJson('/api/superadmin/reports/platform-revenue')
            ->assertForbidden();
    }
}
