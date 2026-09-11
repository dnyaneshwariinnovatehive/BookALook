<?php

namespace Tests\Feature;

use App\Models\City;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Support\BillingModel;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * Customers see the city they are in, and never an unexplained empty screen.
 *
 * A directory that lists every salon in the country is not a marketplace: none
 * of it is bookable by the person reading it. Scoping to one city is only half
 * the job though — the other half is that a city with nothing in it has to say
 * so and offer somewhere else, because an empty list with no explanation reads
 * as a broken app.
 */
class CityScopedDirectoryTest extends TestCase
{
    use DatabaseTransactions;

    public function test_the_directory_only_shows_salons_in_the_asked_for_city(): void
    {
        [$here, $cityA] = $this->givenSalonInItsOwnCity();
        [$elsewhere, $cityB] = $this->givenSalonInItsOwnCity();

        $listed = $this->getJson("/api/customer/salons?city_id={$cityA->id}")
            ->assertStatus(200)
            ->json();

        $ids = collect($listed['salons'])->pluck('id');

        $this->assertContains($here->id, $ids);
        $this->assertNotContains($elsewhere->id, $ids);
        // The app names the market it is showing, so "nothing here" can be told
        // apart from "something is broken".
        $this->assertSame($cityA->name, $listed['city']['name']);
        $this->assertNotSame($cityB->id, $listed['city']['id']);
    }

    public function test_a_signed_in_customer_gets_their_saved_city_without_asking(): void
    {
        [$salon, $city] = $this->givenSalonInItsOwnCity();

        $customer = $this->givenCustomer();
        $customer->forceFill(['city_id' => $city->id])->save();

        $listed = $this->actingAs($customer, 'sanctum')
            ->getJson('/api/customer/salons')
            ->assertStatus(200)
            ->json();

        $this->assertSame($city->id, $listed['city']['id']);
        $this->assertContains($salon->id, collect($listed['salons'])->pluck('id'));
    }

    public function test_an_explicit_city_beats_the_saved_one(): void
    {
        [$savedSalon, $savedCity] = $this->givenSalonInItsOwnCity();
        [$askedSalon, $askedCity] = $this->givenSalonInItsOwnCity();

        $customer = $this->givenCustomer();
        $customer->forceFill(['city_id' => $savedCity->id])->save();

        $listed = $this->actingAs($customer, 'sanctum')
            ->getJson("/api/customer/salons?city_id={$askedCity->id}")
            ->assertStatus(200)
            ->json();

        // Someone who deliberately switched city must stay switched — booking
        // for a parent in another town is a real thing people do.
        $this->assertSame($askedCity->id, $listed['city']['id']);
        $this->assertContains($askedSalon->id, collect($listed['salons'])->pluck('id'));
        $this->assertNotContains($savedSalon->id, collect($listed['salons'])->pluck('id'));
    }

    public function test_an_empty_city_offers_somewhere_that_is_not_empty(): void
    {
        $this->givenSalonInItsOwnCity();

        $barren = City::create([
            'name' => 'Nowhere ' . Str()->random(6),
            'state' => 'Testland',
            'is_active' => true,
        ]);

        $listed = $this->getJson("/api/customer/salons?city_id={$barren->id}")
            ->assertStatus(200)
            ->json();

        $this->assertEmpty($listed['salons']);
        // An empty list on its own is a dead end.
        $this->assertNotNull($listed['suggested_city']);
        $this->assertNotEmpty($listed['suggested_salons']);
        $this->assertNotSame($barren->id, $listed['suggested_city']['id']);
    }

    public function test_the_city_list_only_offers_cities_with_salons_in_them(): void
    {
        [, $live] = $this->givenSalonInItsOwnCity();

        $barren = City::create([
            'name' => 'Nowhere ' . Str()->random(6),
            'state' => 'Testland',
            'is_active' => true,
        ]);

        $serviceable = collect($this->getJson('/api/cities?serviceable=1')->assertStatus(200)->json());
        $everything = collect($this->getJson('/api/cities')->assertStatus(200)->json());

        $this->assertContains($live->id, $serviceable->pluck('id'));
        // Offering a city with nothing in it sends a customer to a dead end.
        $this->assertNotContains($barren->id, $serviceable->pluck('id'));

        // Partner onboarding still needs every city, so the full list stays.
        $this->assertContains($barren->id, $everything->pluck('id'));

        $row = $serviceable->firstWhere('id', $live->id);
        $this->assertGreaterThanOrEqual(1, $row['salon_count']);
    }

    public function test_a_customer_can_change_the_city_they_shop_in(): void
    {
        [, $city] = $this->givenSalonInItsOwnCity();
        $customer = $this->givenCustomer();

        $this->actingAs($customer, 'sanctum')
            ->putJson('/api/customer/profile/city', ['city_id' => $city->id])
            ->assertStatus(200)
            ->assertJsonPath('city.id', $city->id);

        $this->assertSame($city->id, $customer->fresh()->city_id);
    }

    // ----------------------------------------------------------------- setup

    /** @return array{0: Salon, 1: City} */
    private function givenSalonInItsOwnCity(): array
    {
        $unique = substr(bin2hex(random_bytes(6)), 0, 10);

        $city = City::create([
            'name' => "Testville {$unique}",
            'state' => 'Testland',
            'is_active' => true,
        ]);

        $admin = User::create([
            'name' => "Owner {$unique}",
            'phone' => '9' . substr((string) crc32($unique), 0, 9),
            'password_hash' => 'x',
            'role' => 'admin',
            'is_active' => true,
        ]);

        $salon = Salon::create([
            'admin_id' => $admin->id,
            'name' => "City Salon {$unique}",
            'slug' => "city-salon-{$unique}",
            'address' => 'Test address',
            'city_id' => $city->id,
            'submitted_by' => $admin->id,
            'status' => 'active',
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

        return [$salon, $city];
    }

    private function givenCustomer(): User
    {
        $unique = substr(bin2hex(random_bytes(6)), 0, 10);

        return User::create([
            'name' => "Shopper {$unique}",
            'phone' => '7' . substr((string) crc32($unique . 'c'), 0, 9),
            'password_hash' => 'x',
            'role' => 'customer',
            'is_active' => true,
        ]);
    }
}
