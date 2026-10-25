<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\City;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\ServiceProvider;
use App\Models\SubArea;
use App\Models\SubscriptionPaymentRequest;
use App\Models\SubscriptionPlan;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Starter and Growth differ only in insights, a salon owner sees exactly what
 * the plan includes, and a retired plan can be deleted without losing the
 * history of salons that once bought it.
 */
class PlanInsightsAndDeletionTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;
    private Salon $salon;
    private ServiceProvider $provider;

    private const GROWTH_KEYS = [
        'period', 'repeat_customers', 'peak_hours', 'areas', 'gender_mix', 'visit_gap',
        'staff_deep_dive', 'recommended_combos', 'upsell_links', 'quiet_hour_offers',
        'slow_services', 'win_back',
    ];

    protected function setUp(): void
    {
        parent::setUp();

        $city = City::create(['name' => 'Pune', 'state' => 'Maharashtra', 'is_active' => true]);
        $area = SubArea::create(['name' => 'Kothrud', 'city_id' => $city->id, 'is_active' => true]);

        $this->owner = User::create([
            'role' => 'admin', 'name' => 'Owner', 'phone' => '9820001001', 'password_hash' => bcrypt('x'),
        ]);

        $this->salon = Salon::create([
            'admin_id' => $this->owner->id, 'city_id' => $city->id, 'sub_area_id' => $area->id,
            'name' => 'Plan Test Salon', 'slug' => 'plan-test-'.Str::random(6), 'address' => 'Pune',
            'status' => 'active', 'submitted_by' => $this->owner->id,
        ]);

        $providerUser = User::create([
            'role' => 'service_provider', 'name' => 'Asha', 'phone' => '9820001002', 'password_hash' => bcrypt('x'),
        ]);
        $this->provider = ServiceProvider::create([
            'user_id' => $providerUser->id, 'salon_id' => $this->salon->id, 'is_active' => true,
        ]);

        // A regular who stopped coming, so the Growth sections have data.
        foreach ([200, 150, 100] as $daysAgo) {
            Appointment::create([
                'salon_id' => $this->salon->id,
                'appointed_provider_id' => $this->provider->id,
                'serving_provider_id' => $this->provider->id,
                'booking_source' => 'walk_in',
                'appointment_date' => now()->subDays($daysAgo)->toDateString(),
                'start_time' => '11:00:00', 'end_time' => '11:30:00',
                'status' => 'completed', 'total_amount' => 600, 'final_billed_amount' => 600,
                'walk_in_customer_name' => 'Meera', 'walk_in_customer_phone' => '9811100000',
                'walk_in_customer_gender' => 'female',
            ]);
        }
        Appointment::create([
            'salon_id' => $this->salon->id,
            'appointed_provider_id' => $this->provider->id,
            'serving_provider_id' => $this->provider->id,
            'booking_source' => 'walk_in',
            'appointment_date' => now()->subDays(3)->toDateString(),
            'start_time' => '15:00:00', 'end_time' => '15:30:00',
            'status' => 'completed', 'total_amount' => 400, 'final_billed_amount' => 400,
            'walk_in_customer_name' => 'Ravi', 'walk_in_customer_phone' => '9811100001',
        ]);
    }

    private function plan(string $name, bool $growth, string $level = 'basic'): SubscriptionPlan
    {
        return SubscriptionPlan::create([
            'name' => $name, 'price' => $growth ? 2999 : 1999, 'validity_days' => 30,
            'has_advanced_insights' => $growth,
            'has_upsell_recommendations' => $level,
            'has_cross_sell_recommendations' => $level,
        ]);
    }

    private function subscribe(SubscriptionPlan $plan, string $endDate = null, string $status = 'active'): SalonSubscription
    {
        return SalonSubscription::create([
            'salon_id' => $this->salon->id, 'plan_id' => $plan->id, 'billing_type' => 'subscription',
            'start_date' => now()->subDays(40)->toDateString(),
            'end_date' => $endDate ?? now()->addDays(20)->toDateString(),
            'status' => $status,
        ]);
    }

    private function insights(string $query = '')
    {
        return $this->actingAs($this->owner, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salon->id}/insights{$query}")
            ->assertOk();
    }

    public function test_starter_owner_sees_basic_insights_and_growth_as_locked(): void
    {
        $this->subscribe($this->plan('Starter', growth: false));

        $response = $this->insights('?days=365');
        $data = $response->json('data');

        $this->assertFalse($data['advanced']);
        $this->assertSame([30], $data['periods']);
        foreach (['overview', 'services', 'basic_analytics', 'retention_funnel', 'cross_sell', 'upsell'] as $key) {
            $this->assertArrayHasKey($key, $data, "Starter should include {$key}");
        }
        foreach (self::GROWTH_KEYS as $key) {
            $this->assertArrayNotHasKey($key, $data, "Starter must not include {$key}");
        }

        $locked = collect($response->json('locked'))->pluck('key')->all();
        foreach (self::GROWTH_KEYS as $key) {
            $this->assertContains($key, $locked);
        }
        $this->assertContains('upsell_advanced', $locked);
        $this->assertContains('cross_sell_advanced', $locked);
    }

    public function test_a_plan_saying_none_still_gets_basic_suggestions(): void
    {
        $this->subscribe($this->plan('Old Starter', growth: false, level: 'none'));

        $data = $this->insights()->json('data');

        $this->assertArrayHasKey('cross_sell', $data);
        $this->assertArrayHasKey('upsell', $data);
    }

    public function test_growth_owner_gets_every_section_and_can_change_the_window(): void
    {
        $this->subscribe($this->plan('Growth', growth: true, level: 'advanced'));

        $response = $this->insights('?days=365');
        $data = $response->json('data');

        $this->assertTrue($data['advanced']);
        $this->assertSame([30, 90, 365], $data['periods']);
        $this->assertSame([], $response->json('locked'));
        foreach (self::GROWTH_KEYS as $key) {
            $this->assertArrayHasKey($key, $data, "Growth should include {$key}");
        }

        $this->assertSame(365, $data['period']['days']);
        $this->assertEquals(2200, $data['period']['metrics']['revenue']['current']);

        // Meera came three times and has been away 100 days.
        $this->assertSame('Meera', $data['win_back'][0]['name']);
        $this->assertSame('9811100000', $data['win_back'][0]['phone']);

        $this->assertSame(50, $data['visit_gap']['average_gap_days']);
        // The 200-day-old visit is outside the six-month window.
        $this->assertSame(2, $data['gender_mix']['overall']['female']);
        $this->assertSame(1, $data['gender_mix']['overall']['unknown']);
        $this->assertSame('Asha', $data['staff_deep_dive'][0]['name']);
    }

    public function test_an_unknown_window_falls_back_to_thirty_days(): void
    {
        $this->subscribe($this->plan('Growth', growth: true, level: 'advanced'));

        $this->assertSame(30, $this->insights('?days=7')->json('data.period.days'));
    }

    public function test_salons_can_no_longer_start_whatsapp_campaigns(): void
    {
        $this->actingAs($this->owner, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salon->id}/campaigns", [])
            ->assertStatus(405);
    }

    private function superAdmin(): User
    {
        return User::create([
            'role' => 'superadmin', 'name' => 'BookALook', 'phone' => '9820001999', 'password_hash' => bcrypt('x'),
        ]);
    }

    public function test_a_plan_with_only_ended_subscriptions_can_be_deleted_and_history_survives(): void
    {
        $plan = $this->plan('Test 3 day', growth: false);
        // Ended days ago, but nothing flipped its status to expired.
        $old = $this->subscribe($plan, endDate: now()->subDays(3)->toDateString());

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->deleteJson("/api/superadmin/subscriptions/plans/{$plan->id}")
            ->assertOk();

        $this->assertSoftDeleted('subscription_plans', ['id' => $plan->id]);
        $this->assertFalse(SubscriptionPlan::whereKey($plan->id)->exists());
        $this->assertSame('Test 3 day', $old->fresh()->plan->name);
    }

    public function test_a_plan_still_running_for_a_salon_cannot_be_deleted(): void
    {
        $plan = $this->plan('Starter', growth: false);
        $this->subscribe($plan);

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->deleteJson("/api/superadmin/subscriptions/plans/{$plan->id}")
            ->assertStatus(400);

        $this->assertNotSoftDeleted('subscription_plans', ['id' => $plan->id]);
    }

    public function test_a_plan_with_a_payment_waiting_cannot_be_deleted(): void
    {
        $plan = $this->plan('Test 3 day', growth: false);
        SubscriptionPaymentRequest::create([
            'salon_id' => $this->salon->id, 'subscription_plan_id' => $plan->id,
            'billing_type' => 'subscription', 'screenshot_url' => 'https://example.test/s.png', 'status' => 'pending',
        ]);

        $this->actingAs($this->superAdmin(), 'sanctum')
            ->deleteJson("/api/superadmin/subscriptions/plans/{$plan->id}")
            ->assertStatus(400)
            ->assertJsonFragment(['success' => false]);

        $this->assertNotSoftDeleted('subscription_plans', ['id' => $plan->id]);
    }
}
