<?php

namespace Tests\Feature;

use App\Console\Commands\CheckSubscriptions;
use App\Models\Notification;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\ServiceProvider;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Services\SalonAccessService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * What happens when a salon stops paying.
 *
 * Runs in a transaction so it can use the development database without
 * leaving anything behind.
 */
class SubscriptionLockdownTest extends TestCase
{
    use DatabaseTransactions;

    public function test_an_expired_salon_is_not_serviceable_to_customers(): void
    {
        [$salon] = $this->fixture();
        $this->givenSubscription($salon, endedDaysAgo: 3);

        // The detail page says so plainly...
        $this->getJson("/api/customer/salons/{$salon->id}")
            ->assertStatus(200)
            ->assertJsonPath('salon.is_bookable', false);

        // ...and so does the directory, which used to read a SuperAdmin
        // endpoint that knew nothing about subscriptions.
        $listed = $this->getJson("/api/customer/salons?city_id={$salon->city_id}")
            ->assertStatus(200)
            ->json('salons');
        $row = collect($listed)->firstWhere('id', $salon->id);

        $this->assertNotNull($row);
        $this->assertFalse($row['is_serviceable']);
        $this->assertNotNull($row['unavailable_reason']);
    }

    public function test_a_paid_salon_stays_serviceable(): void
    {
        [$salon] = $this->fixture();
        $this->givenSubscription($salon, endsInDays: 20);

        $listed = $this->getJson("/api/customer/salons?city_id={$salon->city_id}")
            ->assertStatus(200)
            ->json('salons');
        $row = collect($listed)->firstWhere('id', $salon->id);

        $this->assertNotNull($row);
        $this->assertTrue($row['is_serviceable']);
    }

    public function test_the_features_close_for_both_the_owner_and_the_staff(): void
    {
        [$salon, $admin, $provider] = $this->fixture();
        $this->givenSubscription($salon, endedDaysAgo: 1);

        // A lock drawn only in the app would be paint; the API has to refuse.
        foreach ([$admin, $provider->user] as $actor) {
            $this->actingAs($actor, 'sanctum')
                ->getJson("/api/partner/salons/{$salon->id}/appointments")
                ->assertStatus(402)
                ->assertJsonPath('subscription_required', true);

            $this->actingAs($actor, 'sanctum')
                ->getJson("/api/partner/salons/{$salon->id}/walk-in/options")
                ->assertStatus(402);

            $this->actingAs($actor, 'sanctum')
                ->postJson("/api/partner/salons/{$salon->id}/check-in/resolve", ['qr_token' => 'x'])
                ->assertStatus(402);
        }

        $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/staff")
            ->assertStatus(402);

        $this->actingAs($provider->user, 'sanctum')
            ->getJson('/api/partner/me/payroll')
            ->assertStatus(402);
    }

    public function test_the_way_out_of_the_lock_stays_open(): void
    {
        [$salon, $admin] = $this->fixture();
        $this->givenSubscription($salon, endedDaysAgo: 1);

        // A salon that cannot reach the renew button could never recover.
        $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/subscription")
            ->assertStatus(200);

        $this->actingAs($admin, 'sanctum')
            ->getJson('/api/partner/subscription/plans')
            ->assertStatus(200);

        // Coins can pay for the renewal, so the wallet stays reachable too.
        $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/wallet")
            ->assertStatus(200);

        $this->actingAs($admin, 'sanctum')
            ->getJson('/api/partner/notifications')
            ->assertStatus(200);
    }

    public function test_staff_are_told_who_to_call(): void
    {
        [$salon, $admin, $provider] = $this->fixture();
        $this->givenSubscription($salon, endedDaysAgo: 5);

        $body = $this->actingAs($provider->user, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/access")
            ->assertStatus(200)
            ->json();

        $this->assertTrue($body['is_locked']);
        $this->assertSame(SalonAccessService::REASON_SUBSCRIPTION_EXPIRED, $body['reason']);
        // A staff member cannot renew — they can only chase the owner.
        $this->assertFalse($body['can_renew']);
        $this->assertSame($admin->name, $body['salon_admin']['name']);
        $this->assertSame($admin->phone, $body['salon_admin']['phone']);
        $this->assertNotNull($body['expired_on']);

        // The owner gets the renew path instead.
        $ownerView = $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/access")
            ->assertStatus(200)
            ->json();

        $this->assertTrue($ownerView['can_renew']);
    }

    public function test_renewing_reopens_everything(): void
    {
        [$salon, $admin, $provider] = $this->fixture();
        $this->givenSubscription($salon, endedDaysAgo: 2);

        $this->actingAs($provider->user, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments")
            ->assertStatus(402);

        $this->givenSubscription($salon, endsInDays: 30);

        $this->actingAs($provider->user, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments")
            ->assertStatus(200);

        $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/access")
            ->assertStatus(200)
            ->assertJsonPath('is_locked', false);
    }

    public function test_the_owner_is_reminded_once_a_day_until_they_renew(): void
    {
        [$salon, $admin] = $this->fixture();
        $this->givenSubscription($salon, endedDaysAgo: 4);

        $this->artisan('app:check-subscriptions --force-reminders')->assertExitCode(0);

        $reminders = Notification::where('user_id', $admin->id)
            ->where('related_salon_id', $salon->id)
            ->where('type', CheckSubscriptions::TYPE_EXPIRED)
            ->get();

        $this->assertCount(1, $reminders);
        $this->assertSame('renew_subscription', $reminders->first()->data['action']);
        $this->assertStringContainsString($salon->name, $reminders->first()->message);

        // Running again the same day must not stack up duplicates.
        $this->artisan('app:check-subscriptions --force-reminders')->assertExitCode(0);

        $this->assertSame(1, Notification::where('user_id', $admin->id)
            ->where('related_salon_id', $salon->id)
            ->where('type', CheckSubscriptions::TYPE_EXPIRED)
            ->count());
    }

    public function test_a_plan_about_to_end_gets_a_heads_up(): void
    {
        [$salon, $admin] = $this->fixture();
        $this->givenSubscription($salon, endsInDays: 2);

        $this->artisan('app:check-subscriptions --force-reminders')->assertExitCode(0);

        $this->assertDatabaseHas('notifications', [
            'user_id' => $admin->id,
            'related_salon_id' => $salon->id,
            'type' => CheckSubscriptions::TYPE_EXPIRING,
        ]);
    }

    public function test_a_lapsed_plan_is_expired_on_read_not_only_by_the_scheduler(): void
    {
        [$salon] = $this->fixture();

        // Left 'active' with a date in the past, as it would be between runs.
        $subscription = $this->givenSubscription($salon, endedDaysAgo: 1, keepActive: true);
        $this->assertSame('active', $subscription->status);

        $this->assertFalse(app(SalonAccessService::class)->isActive($salon->id));
        $this->assertSame('expired', $subscription->fresh()->status);
    }

    // ------------------------------------------------------------- fixtures

    /** @return array{0: Salon, 1: User, 2: ServiceProvider} */
    private function fixture(): array
    {
        $unique = substr(bin2hex(random_bytes(6)), 0, 10);

        $admin = User::create([
            'name' => "Owner {$unique}",
            'phone' => '9' . substr((string) crc32($unique), 0, 9),
            'password_hash' => 'x',
            'role' => 'admin',
            'is_active' => true,
        ]);

        $salon = Salon::create([
            'admin_id' => $admin->id,
            'name' => "Lock Salon {$unique}",
            'slug' => "lock-salon-{$unique}",
            'address' => 'Test address',
            // Salon registration requires a city, and the customer directory is
            // scoped to one, so a salon without a city is not a state the
            // platform can actually be in.
            'city_id' => \App\Models\City::where('is_active', true)->value('id'),
            'submitted_by' => $admin->id,
            'status' => 'active',
        ]);

        $staffUser = User::create([
            'name' => "Staff {$unique}",
            'phone' => '8' . substr((string) crc32($unique . 'staff'), 0, 9),
            'password_hash' => 'x',
            'role' => 'service_provider',
            'is_active' => true,
        ]);

        $provider = ServiceProvider::create([
            'user_id' => $staffUser->id,
            'salon_id' => $salon->id,
            'is_active' => true,
            'joined_at' => Carbon::today(),
        ])->load('user');

        return [$salon, $admin, $provider];
    }

    private function givenSubscription(
        Salon $salon,
        ?int $endedDaysAgo = null,
        ?int $endsInDays = null,
        bool $keepActive = false
    ): SalonSubscription {
        SalonSubscription::where('salon_id', $salon->id)->update(['status' => 'cancelled']);

        $plan = SubscriptionPlan::first();

        if (! $plan) {
            $this->markTestSkipped('needs a subscription plan');
        }

        $end = $endedDaysAgo !== null
            ? Carbon::today()->subDays($endedDaysAgo)
            : Carbon::today()->addDays($endsInDays ?? 30);

        return SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'billing_type' => \App\Support\BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => $plan->price,
            'start_date' => (clone $end)->subDays(30),
            'end_date' => $end,
            // 'expired' unless the test is deliberately simulating a stale row.
            'status' => ($endedDaysAgo !== null && ! $keepActive) ? 'expired' : 'active',
        ]);
    }
}
