<?php

namespace Tests\Feature;

use App\Models\FirstTimeOffer;
use App\Models\FirstTimeOfferRedemption;
use App\Models\PlatformPolicySetting;
use App\Models\Salon;
use App\Models\ServiceCategory;
use App\Models\ServiceTemplate;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Str;
use Tests\TestCase;

class FirstTimeOfferManagementTest extends TestCase
{
    use DatabaseTransactions;

    private User $superadmin;
    private User $customer;
    private User $partner;
    private ServiceCategory $category;
    private ServiceTemplate $templateA;
    private ServiceTemplate $templateB;
    private Salon $salonA;
    private Salon $salonB;

    protected function setUp(): void
    {
        parent::setUp();

        $this->superadmin = $this->createUser('superadmin');
        $this->customer = $this->createUser('customer');
        $this->partner = $this->createUser('partner');

        $this->category = ServiceCategory::firstOrCreate(
            ['name' => 'Hair & Styling'],
            ['id' => (string) Str::uuid(), 'is_active' => true]
        );

        $this->templateA = ServiceTemplate::create([
            'id' => (string) Str::uuid(),
            'name' => 'Haircut Template ' . Str::random(5),
            'category_id' => $this->category->id,
            'estimated_duration_minutes' => 30,
            'is_active' => true,
        ]);

        $this->templateB = ServiceTemplate::create([
            'id' => (string) Str::uuid(),
            'name' => 'Facial Template ' . Str::random(5),
            'category_id' => $this->category->id,
            'estimated_duration_minutes' => 45,
            'is_active' => true,
        ]);

        $this->salonA = $this->createSalon($this->superadmin, 'Salon Alpha');
        $this->salonB = $this->createSalon($this->superadmin, 'Salon Beta');
    }

    public function test_1_authorized_superadmin_can_list_offers(): void
    {
        $offer = $this->createOffer([
            'name' => 'Listing Test Offer',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
        ]);

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->getJson('/api/superadmin/offers');

        $response->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonFragment(['name' => 'Listing Test Offer']);
    }

    public function test_2_authorized_superadmin_can_view_an_offer(): void
    {
        $offer = $this->createOffer([
            'name' => 'Detailed Offer',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
        ]);
        $offer->serviceTemplates()->attach($this->templateA->id);
        $offer->participatingSalons()->attach($this->salonA->id);

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->getJson("/api/superadmin/offers/{$offer->id}");

        $response->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.name', 'Detailed Offer')
            ->assertJsonPath('data.scope', FirstTimeOffer::SCOPE_NEW_TO_SALON)
            ->assertJsonPath('data.service_templates.0.id', $this->templateA->id)
            ->assertJsonPath('data.participating_salons.0.id', $this->salonA->id);
    }

    public function test_3_superadmin_can_no_longer_create_or_edit_offers(): void
    {
        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson('/api/superadmin/offers', [
                'name' => 'Platform offer',
                'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
                'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
                'discount_value' => 20,
                'service_template_ids' => [$this->templateA->id],
            ])
            ->assertStatus(403)
            ->assertJsonPath('success', false);
        $this->assertDatabaseMissing('first_time_offers', ['name' => 'Platform offer']);

        $offer = $this->createOffer(['name' => 'Salon owned']);
        $this->actingAs($this->superadmin, 'sanctum')
            ->putJson("/api/superadmin/offers/{$offer->id}", ['name' => 'Renamed by superadmin'])
            ->assertStatus(403);
        $this->assertSame('Salon owned', $offer->fresh()->name);
    }

    public function test_4_the_list_names_the_salon_that_made_each_offer(): void
    {
        $this->createOffer(['name' => 'Alpha welcome', 'salon_id' => $this->salonA->id]);
        $this->createOffer(['name' => 'Old platform deal', 'salon_id' => null, 'is_active' => false]);

        $rows = collect($this->actingAs($this->superadmin, 'sanctum')
            ->getJson('/api/superadmin/offers')
            ->assertOk()
            ->json('data'))->keyBy('name');

        $this->assertSame('Salon Alpha', $rows['Alpha welcome']['created_by_salon']['name']);
        $this->assertFalse($rows['Alpha welcome']['is_retired_platform_offer']);
        $this->assertNull($rows['Old platform deal']['created_by_salon']);
        $this->assertTrue($rows['Old platform deal']['is_retired_platform_offer']);

        $this->actingAs($this->superadmin, 'sanctum')
            ->getJson("/api/superadmin/offers?salon_id={$this->salonA->id}")
            ->assertJsonCount(1, 'data');
    }

    public function test_5_superadmin_can_pause_and_delete_a_salons_offer(): void
    {
        $offer = $this->createOffer(['salon_id' => $this->salonA->id]);
        $offer->serviceTemplates()->attach($this->templateA->id);

        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson("/api/superadmin/offers/{$offer->id}/toggle-active", ['is_active' => false])
            ->assertOk();
        $this->assertFalse((bool) $offer->fresh()->is_active);

        $this->actingAs($this->superadmin, 'sanctum')
            ->deleteJson("/api/superadmin/offers/{$offer->id}")
            ->assertOk();
        $this->assertSoftDeleted('first_time_offers', ['id' => $offer->id]);
    }

    public function test_6_a_retired_platform_offer_cannot_be_switched_back_on(): void
    {
        $offer = $this->createOffer(['salon_id' => null, 'is_active' => false]);
        $offer->serviceTemplates()->attach($this->templateA->id);

        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson("/api/superadmin/offers/{$offer->id}/toggle-active", ['is_active' => true])
            ->assertStatus(422);
        $this->assertFalse((bool) $offer->fresh()->is_active);
    }

    public function test_7_an_offer_only_applies_at_the_salon_that_made_it(): void
    {
        $offer = $this->createOffer(['salon_id' => $this->salonA->id, 'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM]);
        $offer->serviceTemplates()->attach($this->templateA->id);
        $platform = $this->createOffer(['salon_id' => null, 'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM]);
        $platform->serviceTemplates()->attach($this->templateA->id);

        $service = app(\App\Services\CustomerOfferEligibilityService::class);
        $atA = $service->getEligibleOffersForCustomerAndSalon($this->customer, $this->salonA->id)->pluck('id');
        $atB = $service->getEligibleOffersForCustomerAndSalon($this->customer, $this->salonB->id)->pluck('id');

        $this->assertContains($offer->id, $atA);
        $this->assertNotContains($platform->id, $atA, 'retired platform offers never apply');
        $this->assertNotContains($offer->id, $atB);
    }

    public function test_16_invalid_or_incomplete_offers_cannot_be_activated(): void
    {
        // Offer with 0 service templates cannot be activated
        $offer = $this->createOffer([
            'name' => 'Incomplete Offer',
            'is_active' => false,
        ]);

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->postJson("/api/superadmin/offers/{$offer->id}/toggle-active", ['is_active' => true]);

        $response->assertStatus(422)
            ->assertJsonPath('success', false);

        $this->assertFalse((bool) $offer->fresh()->is_active);
    }

    public function test_17_disabled_and_expired_offers_report_correct_management_status(): void
    {
        $offer = $this->createOffer([
            'name' => 'Expired Offer',
            'is_active' => true,
            'starts_at' => Carbon::now()->subDays(10),
            'ends_at' => Carbon::now()->subDay(), // Expired yesterday
        ]);

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->getJson("/api/superadmin/offers/{$offer->id}");

        $response->assertStatus(200)
            ->assertJsonPath('data.is_active', true)
            ->assertJsonPath('data.is_valid_now', false);
    }

    public function test_18_unauthenticated_users_cannot_mutate_offers(): void
    {
        $this->getJson('/api/superadmin/offers')->assertStatus(401);
        $this->postJson('/api/superadmin/offers', [])->assertStatus(401);
    }

    public function test_19_customer_and_partner_accounts_cannot_mutate_offers(): void
    {
        // Customer account
        $this->actingAs($this->customer, 'sanctum')
            ->getJson('/api/superadmin/offers')
            ->assertStatus(403);

        $this->actingAs($this->customer, 'sanctum')
            ->postJson('/api/superadmin/offers', ['name' => 'Hacker'])
            ->assertStatus(403);

        // Partner account
        $this->actingAs($this->partner, 'sanctum')
            ->getJson('/api/superadmin/offers')
            ->assertStatus(403);

        $this->actingAs($this->partner, 'sanctum')
            ->postJson('/api/superadmin/offers', ['name' => 'Partner Offer'])
            ->assertStatus(403);
    }

    // --- Helpers ---

    private function createUser(string $role): User
    {
        $unique = Str::random(8);
        return User::create([
            'id' => (string) Str::uuid(),
            'name' => "User {$unique}",
            'phone' => '9' . substr((string) crc32($unique), 0, 9),
            'password_hash' => bcrypt('password'),
            'role' => $role,
            'is_active' => true,
        ]);
    }

    private function createSalon(User $admin, string $name): Salon
    {
        $slug = Str::slug($name) . '-' . Str::random(5);
        return Salon::create([
            'id' => (string) Str::uuid(),
            'admin_id' => $admin->id,
            'name' => $name,
            'slug' => $slug,
            'address' => '456 Test Blvd',
            'submitted_by' => $admin->id,
            'status' => 'active',
        ]);
    }

    private function createOffer(array $overrides = []): FirstTimeOffer
    {
        return FirstTimeOffer::create(array_merge([
            'salon_id' => $this->salonA->id,
            'name' => 'Standard Offer ' . Str::random(5),
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            'max_discount_cap' => 500.0,
            'is_active' => true,
        ], $overrides));
    }
}
