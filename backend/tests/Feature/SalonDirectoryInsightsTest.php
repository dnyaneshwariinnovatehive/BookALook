<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\City;
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
 * The superadmin directory: each salon's bookings, revenue and rating, sorted
 * and filtered by them, plus the figures on a salon's profile.
 */
class SalonDirectoryInsightsTest extends TestCase
{
    use DatabaseTransactions;

    private string $tag;

    protected function setUp(): void
    {
        parent::setUp();
        $this->tag = 'Ins' . Str::random(5);
    }

    private function user(string $role): User
    {
        return User::create([
            'id' => (string) Str::uuid(), 'name' => ucfirst($role), 'phone' => '9' . random_int(100000000, 999999999),
            'password_hash' => 'x', 'role' => $role, 'is_active' => true,
        ]);
    }

    private function salon(string $name, ?City $city = null): Salon
    {
        $owner = $this->user('admin');

        return Salon::create([
            'id' => (string) Str::uuid(), 'admin_id' => $owner->id, 'name' => "{$this->tag} {$name}",
            'slug' => Str::slug($name) . '-' . Str::random(6), 'address' => '1 Test St', 'status' => 'active',
            'submitted_by' => $owner->id, 'city_id' => $city?->id,
        ]);
    }

    private function booking(Salon $salon, string $status, float $total): void
    {
        $provider = \App\Models\ServiceProvider::firstOrCreate(
            ['salon_id' => $salon->id],
            ['id' => (string) Str::uuid(), 'user_id' => $this->user('service_provider')->id, 'is_active' => true],
        );

        Appointment::create([
            'appointed_provider_id' => $provider->id,
            'salon_id' => $salon->id, 'customer_id' => $this->user('customer')->id,
            'booking_source' => 'online', 'appointment_date' => Carbon::today()->toDateString(),
            'start_time' => '10:00:00', 'end_time' => '10:30:00', 'status' => $status,
            'payment_option' => 'advance_only', 'total_amount' => $total,
            'advance_amount' => 0, 'balance_amount' => $total,
        ]);
    }

    private function plan(Salon $salon, SubscriptionPlan $plan, string $billing, int $daysLeft): void
    {
        SalonSubscription::create([
            'salon_id' => $salon->id, 'plan_id' => $plan->id, 'billing_type' => $billing,
            'plan_price_snapshot' => 999, 'start_date' => Carbon::today()->subDays(10),
            'end_date' => Carbon::today()->addDays($daysLeft), 'status' => 'active',
        ]);
    }

    private function list(string $query = ''): array
    {
        return $this->actingAs($this->user('superadmin'), 'sanctum')
            ->getJson("/api/superadmin/salons?search={$this->tag}&per_page=100{$query}")
            ->assertOk()
            ->json();
    }

    public function test_rows_carry_bookings_revenue_and_sort_by_them(): void
    {
        $busy = $this->salon('Busy');
        $quiet = $this->salon('Quiet');
        $this->salon('Empty');

        $this->booking($busy, 'completed', 1000);
        $this->booking($busy, 'completed', 500);
        $this->booking($busy, 'scheduled', 700);
        $this->booking($busy, 'pending_payment', 900); // not a booking yet
        $this->booking($quiet, 'completed', 2000);

        $json = $this->list('&column=bookings&direction=desc');
        $this->assertSame(["{$this->tag} Busy", "{$this->tag} Quiet", "{$this->tag} Empty"], array_column($json['data'], 'name'));

        $busyStats = $json['data'][0]['stats'];
        $this->assertSame(3, $busyStats['bookings']);
        $this->assertSame(2, $busyStats['completed']);
        $this->assertEquals(1500, $busyStats['revenue']);
        $this->assertEquals(750, $busyStats['avg_ticket']);
        $this->assertSame(0, $json['data'][2]['stats']['bookings']);

        // Highest revenue first; a salon with none goes last, not first.
        $byRevenue = $this->list('&column=revenue&direction=desc');
        $this->assertSame(["{$this->tag} Quiet", "{$this->tag} Busy", "{$this->tag} Empty"], array_column($byRevenue['data'], 'name'));

        $lowest = $this->list('&column=revenue&direction=asc');
        $this->assertSame("{$this->tag} Empty", $lowest['data'][0]['name']);

        $this->assertArrayHasKey('summary', $json);
        $this->assertArrayHasKey('cities', $json['filters']);
    }

    public function test_filters_by_city_model_plan_and_plan_state(): void
    {
        $pune = City::create(['id' => (string) Str::uuid(), 'name' => 'Pune ' . $this->tag, 'state' => 'MH', 'is_active' => true]);
        $growth = SubscriptionPlan::create(['name' => 'Growth ' . $this->tag, 'price' => 999, 'validity_days' => 30, 'is_active' => true]);

        $sub = $this->salon('Sub', $pune);
        $this->plan($sub, $growth, BillingModel::SUBSCRIPTION, 3);
        $com = $this->salon('Com');
        $this->plan($com, $growth, BillingModel::COMMISSION, 25);
        $none = $this->salon('None', $pune);

        $names = fn (string $q) => array_column($this->list($q)['data'], 'name');

        $this->assertEqualsCanonicalizing(["{$this->tag} Sub", "{$this->tag} None"], $names("&city_id={$pune->id}"));
        $this->assertSame(["{$this->tag} Com"], $names('&billing=commission'));
        $this->assertSame(["{$this->tag} None"], $names('&billing=none'));
        $this->assertEqualsCanonicalizing(["{$this->tag} Sub", "{$this->tag} Com"], $names("&plan_id={$growth->id}"));
        $this->assertSame(["{$this->tag} Sub"], $names('&plan_state=expiring'));
        $this->assertSame(["{$this->tag} None"], $names('&plan_state=none'));
    }

    public function test_the_profile_carries_insights(): void
    {
        $salon = $this->salon('Profile');
        $this->booking($salon, 'completed', 800);
        $this->booking($salon, 'cancelled', 300);
        $this->booking($salon, 'no_show', 300);

        $this->actingAs($this->user('superadmin'), 'sanctum')
            ->getJson("/api/superadmin/salons/{$salon->id}")
            ->assertOk()
            ->assertJsonPath('data.insights.bookings.total', 3)
            ->assertJsonPath('data.insights.bookings.completed', 1)
            ->assertJsonPath('data.insights.bookings.cancelled', 1)
            ->assertJsonPath('data.insights.bookings.no_show', 1)
            ->assertJsonPath('data.insights.customers', 3)
            ->assertJsonPath('data.insights.rating.average', null);

        $this->assertEquals(800, $this->actingAs($this->user('superadmin'), 'sanctum')
            ->getJson("/api/superadmin/salons/{$salon->id}")->json('data.insights.revenue.total'));
    }

    public function test_assigning_a_collaborator_still_works(): void
    {
        $salon = $this->salon('Collab');
        $collaborator = $this->user('collaborator');

        $this->actingAs($this->user('superadmin'), 'sanctum')
            ->postJson("/api/superadmin/salons/{$salon->id}/assign-collaborator", ['collaborator_id' => $collaborator->id])
            ->assertOk();

        $this->assertSame($collaborator->id, $salon->fresh()->assigned_collaborator_id);
        $row = $this->list('&collaborator_id=' . $collaborator->id)['data'];
        $this->assertSame($collaborator->id, $row[0]['assigned_collaborator']['id']);
    }
}
