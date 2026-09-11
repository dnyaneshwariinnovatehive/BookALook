<?php

namespace Tests\Feature;

use App\Models\City;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Services\GeoService;
use App\Support\BillingModel;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * Nearest first, and honest about how near.
 *
 * Inside one city, distance is the only ordering that means anything — a salon
 * three streets away and one an hour across town are not equivalent because
 * they share a postcode. But a customer who will not share their location must
 * still get a useful list, and a salon the platform has only guessed the
 * position of must not have that guess presented as a measurement.
 */
class DistanceAndLocationTest extends TestCase
{
    use DatabaseTransactions;

    /** Two real points in Pune, about 9 km apart. */
    private const KOREGAON_PARK = [18.5362, 73.8939];
    private const BANER = [18.5590, 73.7868];

    public function test_salons_are_listed_nearest_first(): void
    {
        $city = $this->givenCity('Distance Testville', 18.5204, 73.8567);

        $near = $this->givenSalon($city, 'Near Salon', self::KOREGAON_PARK);
        $far = $this->givenSalon($city, 'Far Salon', self::BANER);

        $listed = $this->getJson(sprintf(
            '/api/customer/salons?city_id=%s&lat=%s&lng=%s',
            $city->id,
            self::KOREGAON_PARK[0],
            self::KOREGAON_PARK[1]
        ))->assertStatus(200)->json();

        $this->assertSame('distance', $listed['sorted_by']);

        $ids = collect($listed['salons'])->pluck('id')->all();
        $this->assertSame([$near->id, $far->id], $ids);

        $rows = collect($listed['salons'])->keyBy('id');
        $this->assertEqualsWithDelta(0.0, $rows[$near->id]['distance_km'], 0.2);
        $this->assertGreaterThan(8, $rows[$far->id]['distance_km']);
    }

    public function test_standing_somewhere_else_reverses_the_order(): void
    {
        $city = $this->givenCity('Flip Testville', 18.5204, 73.8567);

        $a = $this->givenSalon($city, 'KP Salon', self::KOREGAON_PARK);
        $b = $this->givenSalon($city, 'Baner Salon', self::BANER);

        $fromBaner = $this->getJson(sprintf(
            '/api/customer/salons?city_id=%s&lat=%s&lng=%s',
            $city->id,
            self::BANER[0],
            self::BANER[1]
        ))->assertStatus(200)->json('salons');

        // The nearest salon depends on where the customer is standing, which is
        // the entire point of ordering by distance rather than by name.
        $this->assertSame([$b->id, $a->id], collect($fromBaner)->pluck('id')->all());
    }

    public function test_without_a_position_the_list_falls_back_to_rating(): void
    {
        $city = $this->givenCity('Rating Testville', 18.5204, 73.8567);

        $good = $this->givenSalon($city, 'Well Rated', self::BANER, rating: 4.9);
        $poor = $this->givenSalon($city, 'Poorly Rated', self::KOREGAON_PARK, rating: 3.1);

        $listed = $this->getJson("/api/customer/salons?city_id={$city->id}")
            ->assertStatus(200)
            ->json();

        // Refusing location must not degrade the list into something arbitrary.
        $this->assertSame('rating', $listed['sorted_by']);
        $this->assertSame([$good->id, $poor->id], collect($listed['salons'])->pluck('id')->all());
        $this->assertNull(collect($listed['salons'])->first()['distance_km']);
    }

    public function test_a_salon_without_a_pin_is_last_but_still_listed(): void
    {
        $city = $this->givenCity('Unpinned Testville', 18.5204, 73.8567);

        $pinned = $this->givenSalon($city, 'Pinned Salon', self::BANER);
        $unpinned = $this->givenSalon($city, 'Unpinned Salon', null);

        $listed = $this->getJson(sprintf(
            '/api/customer/salons?city_id=%s&lat=%s&lng=%s',
            $city->id,
            self::KOREGAON_PARK[0],
            self::KOREGAON_PARK[1]
        ))->assertStatus(200)->json('salons');

        // A salon that has not pinned itself is still open for business.
        $this->assertSame([$pinned->id, $unpinned->id], collect($listed)->pluck('id')->all());
        $this->assertNull(collect($listed)->firstWhere('id', $unpinned->id)['distance_km']);
    }

    public function test_a_city_centre_placement_is_flagged_as_approximate(): void
    {
        $city = $this->givenCity('Approx Testville', 18.5204, 73.8567);

        $guessed = $this->givenSalon($city, 'Guessed Salon', [18.5204, 73.8567], source: 'city_centre');

        $row = collect($this->getJson(sprintf(
            '/api/customer/salons?city_id=%s&lat=%s&lng=%s',
            $city->id,
            self::KOREGAON_PARK[0],
            self::KOREGAON_PARK[1]
        ))->json('salons'))->firstWhere('id', $guessed->id);

        // The app says "about 4 km" for these; presenting a guess as a
        // measurement is how a customer ends up at the wrong end of town.
        $this->assertTrue($row['distance_is_approximate']);
    }

    public function test_the_nearest_market_is_decided_by_the_nearest_salon(): void
    {
        // Deliberately far from every real salon, so the nearest one really is
        // the test's own and the assertion is about the rule, not the fixture.
        $remote = [27.0000, 71.0000];

        $home = $this->givenCity('Home Testville', $remote[0], $remote[1]);
        $this->givenSalon($home, 'Home Salon', $remote);

        $response = $this->getJson(sprintf(
            '/api/cities/nearest?lat=%s&lng=%s',
            $remote[0],
            $remote[1]
        ))->assertStatus(200)->json();

        $this->assertSame($home->id, $response['city']['id']);
        $this->assertSame('nearest_salon', $response['source']);
        $this->assertTrue($response['in_range']);
    }

    public function test_a_position_picks_the_market_when_nothing_has_been_chosen(): void
    {
        // Far from every real salon so the nearest is unambiguously this one.
        $remote = [24.5000, 70.5000];

        $mine = $this->givenCity('Position Testville', $remote[0], $remote[1]);
        $salon = $this->givenSalon($mine, 'Position Salon', $remote);

        $listed = $this->getJson(sprintf(
            '/api/customer/salons?lat=%s&lng=%s',
            $remote[0],
            $remote[1]
        ))->assertStatus(200)->json();

        // Without this the customer gets the platform's busiest market instead
        // of their own — salons they cannot reach, sorted by how far away.
        $this->assertSame($mine->id, $listed['city']['id']);
        $this->assertContains($salon->id, collect($listed['salons'])->pluck('id'));
    }

    public function test_a_chosen_city_still_beats_the_position(): void
    {
        $remote = [24.6000, 70.6000];

        $standingIn = $this->givenCity('Standing Testville', $remote[0], $remote[1]);
        $this->givenSalon($standingIn, 'Local Salon', $remote);

        $asked = $this->givenCity('Asked Testville', 26.5000, 72.5000);
        $askedSalon = $this->givenSalon($asked, 'Asked Salon', [26.5000, 72.5000]);

        $listed = $this->getJson(sprintf(
            '/api/customer/salons?city_id=%s&lat=%s&lng=%s',
            $asked->id,
            $remote[0],
            $remote[1]
        ))->assertStatus(200)->json();

        // Booking for a parent in another town is a real thing people do, and
        // the GPS must not drag them back.
        $this->assertSame($asked->id, $listed['city']['id']);
        $this->assertContains($askedSalon->id, collect($listed['salons'])->pluck('id'));
    }

    public function test_somewhere_with_no_salons_nearby_says_so_but_still_answers(): void
    {
        $this->givenSalon($this->givenCity('Faraway Testville', 18.5204, 73.8567), 'Only Salon', self::KOREGAON_PARK);

        // The middle of the Bay of Bengal — nowhere near any market.
        $response = $this->getJson('/api/cities/nearest?lat=15.0&lng=88.0')
            ->assertStatus(200)
            ->json();

        $this->assertFalse($response['in_range']);
        $this->assertSame('out_of_range', $response['source']);
        // Still names a city: "we are not near you yet, here is our busiest
        // market" beats a blank screen.
        $this->assertNotNull($response['city']);
    }

    public function test_a_broken_gps_reading_is_refused(): void
    {
        // 0,0 is in the Gulf of Guinea and is what a failed fix looks like.
        $this->getJson('/api/cities/nearest?lat=0&lng=0')->assertStatus(422);
        $this->getJson('/api/cities/nearest?lat=999&lng=999')->assertStatus(422);
    }

    public function test_an_owner_can_pin_their_own_salon_and_nobody_elses(): void
    {
        $city = $this->givenCity('Pin Testville', 18.5204, 73.8567);
        $salon = $this->givenSalon($city, 'My Salon', null);
        $owner = User::find($salon->admin_id);

        $this->actingAs($owner, 'sanctum')
            ->putJson("/api/partner/salons/{$salon->id}/location", [
                'latitude' => self::BANER[0],
                'longitude' => self::BANER[1],
            ])
            ->assertStatus(200)
            ->assertJsonPath('location_source', 'owner');

        $salon->refresh();
        $this->assertEqualsWithDelta(self::BANER[0], (float) $salon->latitude, 0.0001);
        $this->assertSame('owner', $salon->location_source);

        // Somebody else's salon is not theirs to move.
        $other = $this->givenSalon($city, 'Not My Salon', null);

        $this->actingAs($owner, 'sanctum')
            ->putJson("/api/partner/salons/{$other->id}/location", [
                'latitude' => self::BANER[0],
                'longitude' => self::BANER[1],
            ])
            ->assertStatus(404);
    }

    public function test_the_measured_distance_is_right(): void
    {
        $geo = app(GeoService::class);

        // Pune to Mumbai is about 120 km in a straight line.
        $km = $geo->distanceKm(18.5204, 73.8567, 19.0760, 72.8777);

        $this->assertEqualsWithDelta(120, $km, 5);
        $this->assertSame(0.0, $geo->distanceKm(18.5204, 73.8567, 18.5204, 73.8567));
    }

    // ----------------------------------------------------------------- setup

    private function givenCity(string $prefix, float $lat, float $lng): City
    {
        return City::create([
            'name' => $prefix . ' ' . substr(bin2hex(random_bytes(4)), 0, 6),
            'state' => 'Testland',
            'latitude' => $lat,
            'longitude' => $lng,
            'is_active' => true,
        ]);
    }

    /** @param array{0: float, 1: float}|null $at */
    private function givenSalon(
        City $city,
        string $name,
        ?array $at,
        float $rating = 4.0,
        string $source = 'owner'
    ): Salon {
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
            'name' => "{$name} {$unique}",
            'slug' => Str()->slug("{$name}-{$unique}"),
            'address' => 'Test address',
            'city_id' => $city->id,
            'submitted_by' => $admin->id,
            'status' => 'active',
            'avg_rating' => $rating,
            'latitude' => $at[0] ?? null,
            'longitude' => $at[1] ?? null,
            'location_source' => $at === null ? null : $source,
        ]);

        $plan = SubscriptionPlan::first();

        if ($plan) {
            SalonSubscription::create([
                'salon_id' => $salon->id,
                'plan_id' => $plan->id,
                'billing_type' => BillingModel::SUBSCRIPTION,
                'plan_price_snapshot' => $plan->price,
                'start_date' => Carbon::today()->subDay(),
                'end_date' => Carbon::today()->addDays(30),
                'status' => 'active',
            ]);
        }

        return $salon;
    }
}
