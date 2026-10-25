<?php

namespace Tests\Feature;

use App\Models\Appointment;
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
use App\Services\PayrollService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * A walk-in is real work: the staff member who served it earns commission on
 * it exactly as on an online booking, and sees it in their own history —
 * only theirs, not every walk-in the salon has taken.
 */
class WalkInCommissionAndScopeTest extends TestCase
{
    use DatabaseTransactions;

    private string $unique;
    private User $owner;
    private Salon $salon;
    private Service $service;
    private User $janeUser;
    private ServiceProvider $jane;
    private User $raviUser;
    private ServiceProvider $ravi;

    protected function setUp(): void
    {
        parent::setUp();

        $this->unique = substr(bin2hex(random_bytes(6)), 0, 8);
        $this->owner = $this->user('admin', 'own');

        $this->salon = Salon::create([
            'admin_id' => $this->owner->id,
            'name' => "Walkin Salon {$this->unique}",
            'slug' => "walkin-{$this->unique}",
            'address' => '1 Walk Street',
            'status' => 'active',
            'submitted_by' => $this->owner->id,
        ]);

        $plan = SubscriptionPlan::first() ?? SubscriptionPlan::create([
            'name' => 'Growth Plan', 'price' => 999, 'duration_days' => 30, 'is_active' => true,
        ]);
        SalonSubscription::create([
            'salon_id' => $this->salon->id,
            'plan_id' => $plan->id,
            'billing_type' => \App\Support\BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => $plan->price,
            'start_date' => Carbon::today()->subDays(5),
            'end_date' => Carbon::today()->addDays(25),
            'status' => 'active',
        ]);

        for ($d = 0; $d <= 6; $d++) {
            SalonWorkingHour::create([
                'salon_id' => $this->salon->id, 'day_of_week' => $d,
                'open_time' => '00:00:00', 'close_time' => '23:59:00', 'is_closed' => false,
            ]);
        }

        $template = ServiceTemplate::create([
            'category_id' => ServiceCategory::create(['name' => "Hair {$this->unique}", 'is_active' => true])->id,
            'name' => "Cut {$this->unique}",
            'estimated_duration_minutes' => 30,
            'is_active' => true,
        ]);
        $this->service = Service::create([
            'salon_id' => $this->salon->id, 'template_id' => $template->id, 'price' => 500, 'is_active' => true,
        ]);

        [$this->janeUser, $this->jane] = $this->provider('jane', 10);
        [$this->raviUser, $this->ravi] = $this->provider('ravi', 20);
    }

    private function user(string $role, string $tag): User
    {
        return User::create([
            'id' => (string) Str::uuid(),
            'role' => $role,
            'name' => "{$tag} {$this->unique}",
            'phone' => '7'.substr((string) crc32($this->unique.$tag), 0, 9),
            'password_hash' => bcrypt('password'),
            'is_active' => true,
        ]);
    }

    /** @return array{0: User, 1: ServiceProvider} */
    private function provider(string $tag, float $commission): array
    {
        $user = $this->user('service_provider', $tag);
        $provider = ServiceProvider::create([
            'user_id' => $user->id,
            'salon_id' => $this->salon->id,
            'commission_percentage' => $commission,
            'is_active' => true,
        ]);
        for ($d = 0; $d <= 6; $d++) {
            ProviderWorkingHour::create([
                'provider_id' => $provider->id, 'day_of_week' => $d,
                'shift_start' => '00:00:00', 'shift_end' => '23:59:00', 'is_weekly_off' => false,
            ]);
        }
        $provider->services()->attach($this->service->id);

        return [$user, $provider];
    }

    /** Owner adds a walk-in for this provider that starts now, then takes the money. */
    private function servedWalkIn(ServiceProvider $provider, string $name): Appointment
    {
        $created = $this->actingAs($this->owner, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salon->id}/appointments/walk-in", [
                'customer_name' => $name,
                'services' => [$this->service->id],
                'provider_id' => $provider->id,
                'allow_overlap' => true,
            ]);
        $created->assertSuccessful();

        $id = $created->json('appointment.id') ?? $created->json('id');
        $this->assertNotNull($id, 'walk-in id missing: '.$created->getContent());

        $this->actingAs($this->owner, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salon->id}/appointments/{$id}/collect-payment", [
                'payment_mode' => 'cash',
            ])->assertSuccessful();

        return Appointment::findOrFail($id);
    }

    public function test_walk_in_counts_toward_the_serving_providers_commission(): void
    {
        $walkIn = $this->servedWalkIn($this->jane, 'Meera');

        $this->assertSame('completed', $walkIn->status);

        $payroll = app(PayrollService::class);
        $this->assertSame(50.0, $payroll->commissionEarned($this->jane->id, Carbon::today()));
        $this->assertSame(0.0, $payroll->commissionEarned($this->ravi->id, Carbon::today()));

        $breakdown = $payroll->commissionBreakdown($this->jane->id, Carbon::today());
        $this->assertCount(1, $breakdown);
        $this->assertSame('walk_in', $breakdown[0]['source']);
    }

    public function test_walk_in_booked_for_later_and_started_by_the_provider_earns_commission(): void
    {
        $later = now()->addHour()->startOfHour();
        if (! $later->isSameDay(now())) {
            $this->markTestSkipped('needs an hour left in the day');
        }

        $created = $this->actingAs($this->owner, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salon->id}/appointments/walk-in", [
                'customer_name' => 'Later Customer',
                'services' => [$this->service->id],
                'provider_id' => $this->jane->id,
                'start_time' => $later->format('Y-m-d H:i:s'),
                'allow_overlap' => true,
            ])->assertSuccessful();
        $id = $created->json('appointment.id') ?? $created->json('id');

        // The customer turns up at their slot: bring the booking to now so the
        // check-in window is open whatever time the suite runs.
        $this->assertNull(Appointment::find($id)->serving_provider_id);
        Appointment::whereKey($id)->update([
            'start_time' => now()->format('H:i:s'),
            'end_time' => now()->addMinutes(30)->format('H:i:s'),
        ]);

        $this->actingAs($this->janeUser, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salon->id}/appointments/{$id}/start", ['manual' => true, 'reason' => 'Walk-in'])
            ->assertSuccessful();
        $this->actingAs($this->janeUser, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salon->id}/appointments/{$id}/collect-payment", ['payment_mode' => 'upi'])
            ->assertSuccessful();

        $this->assertSame(50.0, app(PayrollService::class)->commissionEarned($this->jane->id, Carbon::today()));
    }

    public function test_provider_history_only_shows_walk_ins_they_served(): void
    {
        $this->servedWalkIn($this->jane, "Meera {$this->unique}");
        $this->servedWalkIn($this->ravi, "Arjun {$this->unique}");

        foreach (['all', 'my', null] as $scope) {
            $query = $scope ? "?scope={$scope}" : '';
            $response = $this->actingAs($this->janeUser, 'sanctum')
                ->getJson("/api/partner/salons/{$this->salon->id}/walk-in/history{$query}")
                ->assertStatus(200);

            $names = collect($response->json('walk_ins'))->pluck('customer_name');
            $this->assertTrue($names->contains("Meera {$this->unique}"), "scope={$scope}");
            $this->assertFalse($names->contains("Arjun {$this->unique}"), "scope={$scope}");
            $this->assertSame(1, $response->json('summary.total_walk_ins'));
        }
    }

    public function test_owner_history_shows_every_walk_in(): void
    {
        $this->servedWalkIn($this->jane, "Meera {$this->unique}");
        $this->servedWalkIn($this->ravi, "Arjun {$this->unique}");

        $names = collect(
            $this->actingAs($this->owner, 'sanctum')
                ->getJson("/api/partner/salons/{$this->salon->id}/walk-in/history")
                ->assertStatus(200)
                ->json('walk_ins')
        )->pluck('customer_name');

        $this->assertTrue($names->contains("Meera {$this->unique}"));
        $this->assertTrue($names->contains("Arjun {$this->unique}"));
    }
}
