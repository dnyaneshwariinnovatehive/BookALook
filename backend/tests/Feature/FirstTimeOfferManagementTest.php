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

    public function test_3_authorized_superadmin_can_create_a_valid_percentage_offer(): void
    {
        $payload = [
            'name' => 'Summer Welcome 25%',
            'description' => '25% off for first timers',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 25.0,
            'max_discount_cap' => 400.0,
            'min_service_price' => 150.0,
            'min_eligible_subtotal' => 300.0,
            'min_total_booking_subtotal' => 500.0,
            'is_active' => true,
            'service_template_ids' => [$this->templateA->id, $this->templateB->id],
        ];

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->postJson('/api/superadmin/offers', $payload);

        $response->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.name', 'Summer Welcome 25%')
            ->assertJsonPath('data.discount_value', '25.00')
            ->assertJsonPath('data.max_discount_cap', '400.00');

        $this->assertDatabaseHas('first_time_offers', [
            'name' => 'Summer Welcome 25%',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
        ]);
    }

    public function test_4_authorized_superadmin_can_create_a_valid_flat_offer(): void
    {
        $payload = [
            'name' => 'Flat 150 Off First Visit',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
            'discount_type' => FirstTimeOffer::TYPE_FLAT,
            'discount_value' => 150.0,
            'max_discount_cap' => 600.0,
            'is_active' => true,
            'service_template_ids' => [$this->templateA->id],
            'salon_ids' => [$this->salonA->id],
        ];

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->postJson('/api/superadmin/offers', $payload);

        $response->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.discount_value', '150.00')
            ->assertJsonPath('data.max_discount_cap', '600.00');

        $this->assertDatabaseHas('first_time_offers', [
            'name' => 'Flat 150 Off First Visit',
            'discount_type' => FirstTimeOffer::TYPE_FLAT,
        ]);
    }

    public function test_5_invalid_eligibility_scope_is_rejected(): void
    {
        $payload = [
            'name' => 'Invalid Scope Offer',
            'scope' => 'invalid_scope_name',
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            'service_template_ids' => [$this->templateA->id],
        ];

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->postJson('/api/superadmin/offers', $payload);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['scope']);
    }

    public function test_6_invalid_discount_type_is_rejected(): void
    {
        $payload = [
            'name' => 'Invalid Type Offer',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => 'bogus_type',
            'discount_value' => 20.0,
            'service_template_ids' => [$this->templateA->id],
        ];

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->postJson('/api/superadmin/offers', $payload);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['discount_type']);
    }

    public function test_7_percentage_outside_configured_limits_is_rejected(): void
    {
        // Platform policy: min 5%, max 50%
        $payloadOver = [
            'name' => 'Too High Percentage',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 55.0, // > 50
            'service_template_ids' => [$this->templateA->id],
        ];

        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson('/api/superadmin/offers', $payloadOver)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['discount_value']);

        $payloadUnder = [
            'name' => 'Too Low Percentage',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 2.0, // < 5
            'service_template_ids' => [$this->templateA->id],
        ];

        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson('/api/superadmin/offers', $payloadUnder)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['discount_value']);
    }

    public function test_8_flat_amount_outside_configured_limits_is_rejected(): void
    {
        // Platform policy: min ₹1, max ₹1,000
        $payloadOver = [
            'name' => 'Too High Flat',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_FLAT,
            'discount_value' => 1200.0, // > 1000
            'service_template_ids' => [$this->templateA->id],
        ];

        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson('/api/superadmin/offers', $payloadOver)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['discount_value']);

        $payloadUnder = [
            'name' => 'Zero Flat',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_FLAT,
            'discount_value' => 0.0, // < 1
            'service_template_ids' => [$this->templateA->id],
        ];

        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson('/api/superadmin/offers', $payloadUnder)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['discount_value']);
    }

    public function test_9_caps_above_platform_limits_are_rejected(): void
    {
        // Platform ceiling cap is ₹5,000
        $payload = [
            'name' => 'Excessive Cap Offer',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 30.0,
            'max_discount_cap' => 6000.0, // > 5000
            'service_template_ids' => [$this->templateA->id],
        ];

        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson('/api/superadmin/offers', $payload)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['max_discount_cap']);
    }

    public function test_10_invalid_minimum_conditions_are_rejected(): void
    {
        $payload = [
            'name' => 'Negative Min Spend',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            'min_service_price' => -50.0, // Negative not allowed
            'service_template_ids' => [$this->templateA->id],
        ];

        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson('/api/superadmin/offers', $payload)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['min_service_price']);
    }

    public function test_11_nonexistent_service_template_ids_are_rejected(): void
    {
        $fakeTemplateId = (string) Str::uuid();

        $payload = [
            'name' => 'Nonexistent Template Offer',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            'service_template_ids' => [$fakeTemplateId],
        ];

        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson('/api/superadmin/offers', $payload)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['service_template_ids.0']);
    }

    public function test_12_nonexistent_salon_ids_are_rejected(): void
    {
        $fakeSalonId = (string) Str::uuid();

        $payload = [
            'name' => 'Nonexistent Salon Offer',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            'service_template_ids' => [$this->templateA->id],
            'salon_ids' => [$fakeSalonId],
        ];

        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson('/api/superadmin/offers', $payload)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['salon_ids.0']);
    }

    public function test_13_duplicate_service_and_salon_selections_are_handled_safely(): void
    {
        $payload = [
            'name' => 'Duplicate Selection Offer',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            // Duplicate templates and salons in input
            'service_template_ids' => [$this->templateA->id, $this->templateA->id],
            'salon_ids' => [$this->salonA->id, $this->salonA->id],
        ];

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->postJson('/api/superadmin/offers', $payload);

        $response->assertStatus(201);
        $offerId = $response->json('data.id');
        $offer = FirstTimeOffer::find($offerId);

        // Assert exactly one pivot record was created without duplicate key error
        $this->assertCount(1, $offer->serviceTemplates);
        $this->assertCount(1, $offer->participatingSalons);
    }

    public function test_14_service_and_salon_mappings_persist_correctly(): void
    {
        $payload = [
            'name' => 'Full Mapped Offer',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
            'discount_type' => FirstTimeOffer::TYPE_FLAT,
            'discount_value' => 100.0,
            'service_template_ids' => [$this->templateA->id, $this->templateB->id],
            'salon_ids' => [$this->salonA->id, $this->salonB->id],
        ];

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->postJson('/api/superadmin/offers', $payload);

        $response->assertStatus(201);
        $offer = FirstTimeOffer::find($response->json('data.id'));

        $this->assertCount(2, $offer->serviceTemplates);
        $this->assertCount(2, $offer->participatingSalons);
    }

    public function test_15_updating_an_offer_does_not_delete_redemption_history(): void
    {
        $offer = $this->createOffer();
        $offer->serviceTemplates()->attach($this->templateA->id);

        // Simulate an existing redemption
        $redemption = FirstTimeOfferRedemption::create([
            'offer_id' => $offer->id,
            'customer_id' => $this->customer->id,
            'salon_id' => $this->salonA->id,
            'status' => FirstTimeOfferRedemption::STATUS_COMMITTED,
            'active_entitlement_key' => $offer->makeEntitlementKey($this->customer->id),
            'scope' => $offer->scope,
            'discount_amount' => 50.0,
            'reserved_at' => Carbon::now(),
            'committed_at' => Carbon::now(),
        ]);

        $updatePayload = [
            'name' => 'Renamed Offer',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 30.0,
            'service_template_ids' => [$this->templateB->id], // Switch template
        ];

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->putJson("/api/superadmin/offers/{$offer->id}", $updatePayload);

        $response->assertStatus(200);

        // Assert redemption record remains intact
        $this->assertDatabaseHas('first_time_offer_redemptions', [
            'id' => $redemption->id,
            'offer_id' => $offer->id,
            'status' => FirstTimeOfferRedemption::STATUS_COMMITTED,
        ]);
        $this->assertSame(1, $offer->fresh()->redemptions()->count());
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

    public function test_20_invalid_update_requests_do_not_leave_partially_updated_configuration(): void
    {
        $offer = $this->createOffer([
            'name' => 'Original Name',
            'discount_value' => 20.0,
        ]);
        $offer->serviceTemplates()->attach($this->templateA->id);

        // Submit invalid update with non-existent template ID
        $invalidPayload = [
            'name' => 'Changed Name Should Rollback',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 30.0,
            'service_template_ids' => [(string) Str::uuid()], // Non-existent
        ];

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->putJson("/api/superadmin/offers/{$offer->id}", $invalidPayload);

        $response->assertStatus(422);

        // Assert database retained original values
        $this->assertSame('Original Name', $offer->fresh()->name);
        $this->assertSame('20.00', (string) $offer->fresh()->discount_value);
        $this->assertTrue($offer->fresh()->serviceTemplates->contains($this->templateA->id));
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
            'name' => 'Standard Offer ' . Str::random(5),
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            'max_discount_cap' => 500.0,
            'is_active' => true,
        ], $overrides));
    }
}
