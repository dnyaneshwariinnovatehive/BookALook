<?php

namespace Tests\Feature;

use App\Models\City;
use App\Models\Combo;
use App\Models\Salon;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceTemplate;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * Browsing a category in Explore.
 *
 * The promise the category tiles make is that everything on the screen does
 * that thing: a customer who tapped Hair has asked for salons offering Hair, and
 * a salon that only does facials is not a near miss, it is the wrong answer.
 * That has to survive the two ways the list can quietly leak — a service the
 * salon has switched off still counting as an offer, and the empty-list
 * fallback dragging in salons from other categories — and it has to survive
 * search too, which is a separate request and would otherwise forget.
 */
class CategoryFilteredExploreTest extends TestCase
{
    use DatabaseTransactions;

    public function test_it_lists_only_salons_offering_that_category(): void
    {
        [$hairSalon, $city] = $this->givenSalonInItsOwnCity();
        [$nailsSalon] = $this->givenSalonInItsOwnCity($city);

        [$hair, $nails] = $this->givenHairAndNails();
        $this->givenService($hairSalon, $hair);
        $this->givenService($nailsSalon, $nails);

        $ids = $this->listedSalonIds($city, ['category_id' => $hair->id]);

        $this->assertContains($hairSalon->id, $ids);
        $this->assertNotContains($nailsSalon->id, $ids);
    }

    public function test_a_service_the_salon_has_switched_off_is_not_an_offer(): void
    {
        [$salon, $city] = $this->givenSalonInItsOwnCity();
        [$hair, $nails] = $this->givenHairAndNails();

        $this->givenService($salon, $hair, isActive: false);

        // The salon still owns a Hair template, so a filter that only looked at
        // the template would happily list it. It cannot be booked, so it must not
        // be offered.
        $this->assertNotContains($salon->id, $this->listedSalonIds($city, ['category_id' => $hair->id]));

        // …while its nails row proves the salon itself is not the reason it is
        // missing.
        $this->givenService($salon, $nails);
        $this->assertContains($salon->id, $this->listedSalonIds($city, ['category_id' => $nails->id]));
    }

    public function test_a_deleted_service_is_not_an_offer_either(): void
    {
        [$salon, $city] = $this->givenSalonInItsOwnCity();
        [$hair] = $this->givenHairAndNails();

        $this->givenService($salon, $hair)->delete();

        $this->assertNotContains($salon->id, $this->listedSalonIds($city, ['category_id' => $hair->id]));
    }

    public function test_a_category_with_no_salons_is_empty_rather_than_filled_with_others(): void
    {
        [$nailsSalon, $city] = $this->givenSalonInItsOwnCity();
        [, $hair] = $this->givenHairAndNails();

        $this->givenService($nailsSalon, $this->givenCategory('Nails'));

        $listed = $this->getJson("/api/customer/salons?city_id={$city->id}&category_id={$hair->id}")
            ->assertStatus(200)
            ->json();

        // Showing the nails salon here would tell the customer it does hair.
        $this->assertEmpty($listed['salons']);
        $this->assertEmpty($listed['suggested_salons']);
        $this->assertNull($listed['suggested_city']);
    }

    public function test_combo_lists_only_salons_with_a_live_package(): void
    {
        [$withCombo, $city] = $this->givenSalonInItsOwnCity();
        [$withDisabledCombo] = $this->givenSalonInItsOwnCity($city);
        [$plain] = $this->givenSalonInItsOwnCity($city);

        Combo::create(['salon_id' => $withCombo->id, 'name' => 'Hair + Facial', 'advance_percentage' => 10, 'is_active' => true]);
        Combo::create(['salon_id' => $withDisabledCombo->id, 'name' => 'Retired', 'advance_percentage' => 10, 'is_active' => false]);

        $ids = $this->listedSalonIds($city, ['category_id' => Combo::CATEGORY_SENTINEL]);

        $this->assertContains($withCombo->id, $ids);
        $this->assertNotContains($withDisabledCombo->id, $ids);
        $this->assertNotContains($plain->id, $ids);
    }

    public function test_the_combo_sentinel_is_matched_however_the_app_spells_it(): void
    {
        [$salon, $city] = $this->givenSalonInItsOwnCity();
        Combo::create(['salon_id' => $salon->id, 'name' => 'Any', 'advance_percentage' => 10, 'is_active' => true]);

        $this->assertContains(
            $salon->id,
            $this->listedSalonIds($city, ['category_id' => 'Combo'])
        );
    }

    public function test_ordinary_explore_is_untouched_by_any_of_this(): void
    {
        [$hairSalon, $city] = $this->givenSalonInItsOwnCity();
        [$nailsSalon] = $this->givenSalonInItsOwnCity($city);

        [$hair, $nails] = $this->givenHairAndNails();
        $this->givenService($hairSalon, $hair);
        $this->givenService($nailsSalon, $nails);

        $ids = $this->listedSalonIds($city);

        $this->assertContains($hairSalon->id, $ids);
        $this->assertContains($nailsSalon->id, $ids);
    }

    public function test_search_stays_inside_the_category(): void
    {
        [$hairSalon, $city] = $this->givenSalonInItsOwnCity();
        [$nailsSalon] = $this->givenSalonInItsOwnCity($city);

        [$hair, $nails] = $this->givenHairAndNails();
        $this->givenService($hairSalon, $hair, name: 'Haircut');
        $this->givenService($nailsSalon, $nails, name: 'Haircut');

        $results = $this->getJson("/api/customer/search?q=haircut&city_id={$city->id}&category_id={$hair->id}")
            ->assertStatus(200)
            ->json();

        $offeredBy = collect($results['services'])->pluck('salon.id');

        $this->assertContains($hairSalon->id, $offeredBy);
        $this->assertNotContains($nailsSalon->id, $offeredBy);
    }

    public function test_search_without_a_category_still_searches_everything(): void
    {
        [$hairSalon, $city] = $this->givenSalonInItsOwnCity();
        [$nailsSalon] = $this->givenSalonInItsOwnCity($city);

        [$hair, $nails] = $this->givenHairAndNails();
        $this->givenService($hairSalon, $hair, name: 'Haircut');
        $this->givenService($nailsSalon, $nails, name: 'Haircut');

        $offeredBy = collect(
            $this->getJson("/api/customer/search?q=haircut&city_id={$city->id}")->assertStatus(200)->json()['services']
        )->pluck('salon.id');

        $this->assertContains($hairSalon->id, $offeredBy);
        $this->assertContains($nailsSalon->id, $offeredBy);
    }

    public function test_a_search_refuses_a_category_that_does_not_exist(): void
    {
        [, $city] = $this->givenSalonInItsOwnCity();

        $this->getJson("/api/customer/search?q=haircut&city_id={$city->id}&category_id=" . Str()->uuid())
            ->assertStatus(422);
    }

    // ----------------------------------------------------------------- setup

    /** @return array{0: Salon, 1: City} */
    private function givenSalonInItsOwnCity(?City $city = null): array
    {
        $unique = substr(bin2hex(random_bytes(6)), 0, 10);

        $city ??= City::create([
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
            'name' => "Category Salon {$unique}",
            'slug' => "category-salon-{$unique}",
            'address' => 'Test address',
            'city_id' => $city->id,
            'submitted_by' => $admin->id,
            'status' => 'active',
        ]);

        return [$salon, $city];
    }

    /** @return array{0: ServiceCategory, 1: ServiceCategory} */
    private function givenHairAndNails(): array
    {
        return [$this->givenCategory('Hair'), $this->givenCategory('Nails')];
    }

    private function givenCategory(string $name): ServiceCategory
    {
        $unique = substr(bin2hex(random_bytes(6)), 0, 8);

        return ServiceCategory::create([
            'name' => "{$name} {$unique}",
            'is_custom' => false,
            'is_active' => true,
            'display_order' => 0,
        ]);
    }

    private function givenService(Salon $salon, ServiceCategory $category, bool $isActive = true, ?string $name = null): Service
    {
        $template = ServiceTemplate::create([
            'category_id' => $category->id,
            'name' => $name ?? "{$category->name} Service",
            'estimated_duration_minutes' => 30,
            'is_custom' => false,
            'is_active' => true,
        ]);

        return Service::create([
            'salon_id' => $salon->id,
            'template_id' => $template->id,
            'price' => 500,
            'advance_percentage' => 20,
            'is_active' => $isActive,
        ]);
    }

    /** @return array<int, string> */
    private function listedSalonIds(City $city, array $query = []): array
    {
        $listed = $this->getJson('/api/customer/salons?' . http_build_query(
            ['city_id' => $city->id] + $query
        ))->assertStatus(200)->json();

        return collect($listed['salons'])->pluck('id')->all();
    }
}
