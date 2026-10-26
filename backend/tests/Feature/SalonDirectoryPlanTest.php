<?php

namespace Tests\Feature;

use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Support\BillingModel;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The superadmin salon directory shows the plan each salon is on right now.
 */
class SalonDirectoryPlanTest extends TestCase
{
    use DatabaseTransactions;

    public function test_each_salon_carries_its_current_plan(): void
    {
        $superadmin = $this->user('superadmin');
        $plan = SubscriptionPlan::create(['name' => 'Growth ' . Str::random(4), 'price' => 2999, 'validity_days' => 30, 'is_active' => true]);

        $onPlan = $this->salon('Dir On Plan');
        SalonSubscription::create([
            'salon_id' => $onPlan->id, 'plan_id' => $plan->id,
            'billing_type' => BillingModel::SUBSCRIPTION, 'plan_price_snapshot' => 2999,
            'start_date' => Carbon::today()->subDays(20), 'end_date' => Carbon::today()->addDays(3),
            'status' => 'active',
        ]);

        $lapsed = $this->salon('Dir Lapsed');
        SalonSubscription::create([
            'salon_id' => $lapsed->id, 'plan_id' => $plan->id,
            'billing_type' => BillingModel::COMMISSION, 'plan_price_snapshot' => 0,
            'start_date' => Carbon::today()->subDays(40), 'end_date' => Carbon::today()->subDay(),
            'status' => 'active',
        ]);

        $none = $this->salon('Dir No Plan');

        $rows = collect($this->actingAs($superadmin, 'sanctum')
            ->getJson('/api/superadmin/salons?search=Dir&per_page=100')
            ->assertOk()
            ->json('data'))->keyBy('id');

        $current = $rows[$onPlan->id]['current_plan'];
        $this->assertSame($plan->name, $current['name']);
        $this->assertSame('Subscription Plan', $current['billing_label']);
        $this->assertSame(3, $current['days_left']);
        $this->assertFalse($current['lapsed']);

        $this->assertTrue($rows[$lapsed->id]['current_plan']['lapsed']);
        $this->assertSame('Commission Model', $rows[$lapsed->id]['current_plan']['billing_label']);

        $this->assertNull($rows[$none->id]['current_plan']);
    }

    public function test_the_directory_sorts_by_plan(): void
    {
        $this->actingAs($this->user('superadmin'), 'sanctum')
            ->getJson('/api/superadmin/salons?column=plan&direction=asc')
            ->assertOk();
    }

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
            'slug' => Str::slug($name) . '-' . Str::random(5), 'address' => '1 Test St',
            'status' => 'active', 'submitted_by' => $owner->id,
        ]);
    }
}
