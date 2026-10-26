<?php

namespace Tests\Feature;

use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPaymentRequest;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Support\BillingModel;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The plans & billing dashboard: each salon row carries who to call, where it
 * is, its plan price, and what it has paid so far.
 */
class SubscriptionDashboardDataTest extends TestCase
{
    use DatabaseTransactions;

    public function test_salon_rows_carry_contact_plan_and_payment_totals(): void
    {
        $admin = User::create(['id' => (string) Str::uuid(), 'name' => 'Super', 'phone' => '9'.random_int(100000000, 999999999), 'password_hash' => 'x', 'role' => 'superadmin', 'is_active' => true]);
        $owner = User::create(['id' => (string) Str::uuid(), 'name' => 'Owner Dash', 'phone' => '9'.random_int(100000000, 999999999), 'password_hash' => 'x', 'role' => 'admin', 'is_active' => true]);
        $salon = Salon::create(['id' => (string) Str::uuid(), 'admin_id' => $owner->id, 'name' => 'Dash Salon', 'slug' => 'dash-'.Str::random(5), 'address' => 'x', 'status' => 'active', 'submitted_by' => $owner->id]);
        $plan = SubscriptionPlan::create(['name' => 'Dash Plan '.Str::random(4), 'price' => 1999, 'validity_days' => 30, 'is_active' => true]);

        SalonSubscription::create([
            'salon_id' => $salon->id, 'plan_id' => $plan->id, 'billing_type' => BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => 1999, 'start_date' => Carbon::today()->subDays(3), 'end_date' => Carbon::today()->addDays(27), 'status' => 'active',
        ]);
        foreach ([['approved', 1999], ['approved', 1500], ['pending', 1999], ['rejected', 100]] as [$status, $amount]) {
            SubscriptionPaymentRequest::create([
                'salon_id' => $salon->id, 'subscription_plan_id' => $plan->id, 'billing_type' => BillingModel::SUBSCRIPTION,
                'screenshot_url' => 'https://example.com/s.png', 'status' => $status, 'amount_payable_inr' => $amount,
            ]);
        }

        $row = collect($this->actingAs($admin, 'sanctum')->getJson('/api/superadmin/subscriptions/plans')->assertOk()->json('salons'))
            ->firstWhere('id', $salon->id);

        $this->assertSame($owner->phone, $row['owner_phone']);
        $this->assertSame('active', $row['salon_status']);
        $this->assertEquals(1999, $row['plan_price']);
        $this->assertSame(30, $row['plan_validity_days']);
        $this->assertEquals(3499, $row['lifetime_paid']);
        $this->assertSame(2, $row['payments_count']);
        $this->assertSame(1, $row['pending_requests']);
        $this->assertSame(Carbon::today()->subDays(3)->toDateString(), $row['plan_started']);
    }
}
