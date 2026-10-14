<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\AppointmentService;
use App\Models\FirstTimeOffer;
use App\Models\FirstTimeOfferRedemption;
use App\Models\FirstTimeOfferSalon;
use App\Models\FirstTimeOfferService;
use App\Models\PlatformPolicySetting;
use App\Models\Salon;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceTemplate;
use App\Models\ServiceProvider;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Str;
use Tests\TestCase;

class FirstTimeOfferSchemaTest extends TestCase
{
    use DatabaseTransactions;

    public function test_first_time_offer_can_be_persisted_with_casts(): void
    {
        $offer = FirstTimeOffer::create([
            'name' => 'First Visit 20% Off',
            'description' => 'Get 20% off your first appointment',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.00,
            'max_discount_cap' => 500.00,
            'min_service_price' => 200.00,
            'min_eligible_subtotal' => 400.00,
            'min_total_booking_subtotal' => 500.00,
            'is_active' => true,
            'starts_at' => Carbon::now()->subDay(),
            'ends_at' => Carbon::now()->addDays(30),
            'max_redemptions' => 100,
        ]);

        $this->assertNotNull($offer->id);
        $this->assertTrue(Str::isUuid($offer->id));
        $this->assertSame('20.00', (string) $offer->discount_value);
        $this->assertSame('500.00', (string) $offer->max_discount_cap);
        $this->assertSame('200.00', (string) $offer->min_service_price);
        $this->assertSame('400.00', (string) $offer->min_eligible_subtotal);
        $this->assertSame('500.00', (string) $offer->min_total_booking_subtotal);
        $this->assertTrue($offer->is_active);
        $this->assertTrue($offer->isCurrentlyValid());
        $this->assertFalse($offer->isRedemptionLimitReached());
    }

    public function test_offer_explicit_service_template_mapping(): void
    {
        $offer = FirstTimeOffer::create([
            'name' => 'Explicit Haircut Discount',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_FLAT,
            'discount_value' => 100.00,
        ]);

        $category = ServiceCategory::firstOrCreate(
            ['name' => 'Test Grooming'],
            ['id' => (string) Str::uuid(), 'is_active' => true]
        );

        $templateA = ServiceTemplate::create([
            'name' => 'Template Haircut ' . Str::random(5),
            'category_id' => $category->id,
            'estimated_duration_minutes' => 30,
            'is_active' => true,
        ]);

        $templateB = ServiceTemplate::create([
            'name' => 'Template Beard ' . Str::random(5),
            'category_id' => $category->id,
            'estimated_duration_minutes' => 15,
            'is_active' => true,
        ]);

        // Explicitly target Template A only
        $offer->serviceTemplates()->attach($templateA->id);

        $this->assertTrue($offer->targetsTemplate($templateA->id));
        $this->assertFalse($offer->targetsTemplate($templateB->id));

        $this->assertCount(1, $offer->serviceTemplates);
        $this->assertSame($templateA->id, $offer->serviceTemplates->first()->id);

        // Inverse relationship
        $this->assertTrue($templateA->firstTimeOffers()->where('first_time_offers.id', $offer->id)->exists());
    }

    public function test_offer_participating_salons_mapping(): void
    {
        $admin = $this->createTestUser('admin');
        $salonA = $this->createTestSalon($admin, 'Salon Alpha');
        $salonB = $this->createTestSalon($admin, 'Salon Beta');

        $offer = FirstTimeOffer::create([
            'name' => 'Salon Alpha Exclusive',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 15.00,
        ]);

        // Only Salon A participates
        $offer->participatingSalons()->attach($salonA->id);

        $this->assertTrue($offer->participates($salonA->id));
        $this->assertFalse($offer->participates($salonB->id));

        $this->assertCount(1, $offer->participatingSalons);
        $this->assertTrue($salonA->firstTimeOffers()->where('first_time_offers.id', $offer->id)->exists());
    }

    public function test_platform_policy_settings_hold_discount_limits_and_defaults(): void
    {
        $this->assertEquals(5, PlatformPolicySetting::value('first_time_discount_min_percentage'));
        $this->assertEquals(50, PlatformPolicySetting::value('first_time_discount_max_percentage'));
        $this->assertEquals(500.0, PlatformPolicySetting::value('first_time_discount_default_percentage_cap'));
        $this->assertEquals(1.0, PlatformPolicySetting::value('first_time_discount_min_flat_amount'));
        $this->assertEquals(1000.0, PlatformPolicySetting::value('first_time_discount_max_flat_amount'));
        $this->assertEquals(1000.0, PlatformPolicySetting::value('first_time_discount_default_flat_cap'));
        $this->assertEquals(5000.0, PlatformPolicySetting::value('first_time_discount_platform_max_cap'));
    }

    public function test_appointment_and_services_carry_discount_attribution_columns(): void
    {
        $admin = $this->createTestUser('admin');
        $customer = $this->createTestUser('customer');
        $salon = $this->createTestSalon($admin, 'Attribution Salon');
        $provider = $this->createTestProvider($salon);

        $offer = FirstTimeOffer::create([
            'name' => 'Welcome Offer',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_FLAT,
            'discount_value' => 50.00,
        ]);

        $appointment = Appointment::create([
            'salon_id' => $salon->id,
            'customer_id' => $customer->id,
            'appointed_provider_id' => $provider->id,
            'appointment_date' => Carbon::today()->toDateString(),
            'start_time' => '11:00:00',
            'end_time' => '12:00:00',
            'status' => 'scheduled',
            'total_amount' => 450.00,
            'first_time_offer_id' => $offer->id,
            'first_time_discount_amount' => 50.00,
        ]);

        $this->assertSame($offer->id, $appointment->firstTimeOffer->id);
        $this->assertSame('50.00', (string) $appointment->first_time_discount_amount);

        $category = ServiceCategory::firstOrCreate(
            ['name' => 'Attribution Category'],
            ['id' => (string) Str::uuid(), 'is_active' => true]
        );
        $template = ServiceTemplate::create([
            'name' => 'Attribution Service ' . Str::random(5),
            'category_id' => $category->id,
            'estimated_duration_minutes' => 30,
            'is_active' => true,
        ]);
        $service = Service::create([
            'salon_id' => $salon->id,
            'template_id' => $template->id,
            'price' => 500.00,
            'advance_percentage' => 0,
            'is_active' => true,
        ]);

        $line = AppointmentService::create([
            'appointment_id' => $appointment->id,
            'service_id' => $service->id,
            'price_at_booking' => 450.00,
            'original_service_price' => 500.00,
            'first_time_discount_amount' => 50.00,
            'duration_minutes_at_booking' => 30,
            'line_status' => 'booked',
        ]);

        $this->assertEquals(50.0, (float) $line->first_time_discount_amount);
        $this->assertEquals(450.0, (float) $line->price_at_booking);
    }

    public function test_existing_appointments_continue_working_without_first_time_offer(): void
    {
        $admin = $this->createTestUser('admin');
        $customer = $this->createTestUser('customer');
        $salon = $this->createTestSalon($admin, 'Classic Salon');
        $provider = $this->createTestProvider($salon);

        $appointment = Appointment::create([
            'salon_id' => $salon->id,
            'customer_id' => $customer->id,
            'appointed_provider_id' => $provider->id,
            'appointment_date' => Carbon::today()->toDateString(),
            'start_time' => '14:00:00',
            'end_time' => '15:00:00',
            'status' => 'scheduled',
            'total_amount' => 300.00,
        ]);

        $fresh = $appointment->fresh();
        $this->assertNull($fresh->first_time_offer_id);
        $this->assertEquals(0.0, (float) $fresh->first_time_discount_amount);
        $this->assertNull($fresh->firstTimeOffer);
    }

    public function test_concurrency_protection_rejects_duplicate_active_entitlement_key_at_db_level(): void
    {
        $admin = $this->createTestUser('admin');
        $customer = $this->createTestUser('customer');
        $salon = $this->createTestSalon($admin, 'Locking Salon');

        $offer = FirstTimeOffer::create([
            'name' => 'Concurrent Protected Offer',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 25.00,
        ]);

        $key = $offer->makeEntitlementKey($customer->id);

        // 1. First reservation succeeds
        $res1 = FirstTimeOfferRedemption::create([
            'offer_id' => $offer->id,
            'customer_id' => $customer->id,
            'salon_id' => $salon->id,
            'status' => FirstTimeOfferRedemption::STATUS_RESERVED,
            'active_entitlement_key' => $key,
            'scope' => $offer->scope,
            'discount_amount' => 125.00,
            'reserved_at' => Carbon::now(),
        ]);

        $this->assertNotNull($res1->id);

        // 2. Second concurrent attempt with same active entitlement key MUST throw QueryException
        $this->expectException(QueryException::class);

        FirstTimeOfferRedemption::create([
            'offer_id' => $offer->id,
            'customer_id' => $customer->id,
            'salon_id' => $salon->id,
            'status' => FirstTimeOfferRedemption::STATUS_RESERVED,
            'active_entitlement_key' => $key,
            'scope' => $offer->scope,
            'discount_amount' => 125.00,
            'reserved_at' => Carbon::now(),
        ]);
    }

    public function test_released_reservation_frees_active_entitlement_key_allowing_retry(): void
    {
        $admin = $this->createTestUser('admin');
        $customer = $this->createTestUser('customer');
        $salon = $this->createTestSalon($admin, 'Retry Salon');

        $offer = FirstTimeOffer::create([
            'name' => 'Retryable Offer',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 10.00,
        ]);

        $key = $offer->makeEntitlementKey($customer->id);

        // First hold
        $res1 = FirstTimeOfferRedemption::create([
            'offer_id' => $offer->id,
            'customer_id' => $customer->id,
            'salon_id' => $salon->id,
            'status' => FirstTimeOfferRedemption::STATUS_RESERVED,
            'active_entitlement_key' => $key,
            'scope' => $offer->scope,
            'discount_amount' => 50.00,
            'reserved_at' => Carbon::now(),
        ]);

        // Hold abandoned / expired
        $res1->release('hold_expired');
        $this->assertSame(FirstTimeOfferRedemption::STATUS_RELEASED, $res1->fresh()->status);
        $this->assertNull($res1->fresh()->active_entitlement_key);

        // Customer retries -> second reservation now succeeds cleanly without unique violation
        $res2 = FirstTimeOfferRedemption::create([
            'offer_id' => $offer->id,
            'customer_id' => $customer->id,
            'salon_id' => $salon->id,
            'status' => FirstTimeOfferRedemption::STATUS_RESERVED,
            'active_entitlement_key' => $key,
            'scope' => $offer->scope,
            'discount_amount' => 50.00,
            'reserved_at' => Carbon::now(),
        ]);

        $this->assertNotNull($res2->id);
        $this->assertSame($key, $res2->active_entitlement_key);
    }

    public function test_committed_redemption_increments_offer_redemption_counter(): void
    {
        $admin = $this->createTestUser('admin');
        $customer = $this->createTestUser('customer');
        $salon = $this->createTestSalon($admin, 'Commit Salon');

        $offer = FirstTimeOffer::create([
            'name' => 'Commit Counter Offer',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_FLAT,
            'discount_value' => 80.00,
            'current_redemptions' => 0,
        ]);

        $res = FirstTimeOfferRedemption::create([
            'offer_id' => $offer->id,
            'customer_id' => $customer->id,
            'salon_id' => $salon->id,
            'status' => FirstTimeOfferRedemption::STATUS_RESERVED,
            'active_entitlement_key' => $offer->makeEntitlementKey($customer->id),
            'scope' => $offer->scope,
            'discount_amount' => 80.00,
            'reserved_at' => Carbon::now(),
        ]);

        $this->assertSame(0, $offer->fresh()->current_redemptions);

        $res->commit();

        $this->assertSame(FirstTimeOfferRedemption::STATUS_COMMITTED, $res->fresh()->status);
        $this->assertNotNull($res->fresh()->committed_at);
        $this->assertSame(1, $offer->fresh()->current_redemptions);
    }

    public function test_offer_validation_rules_enforce_platform_policy_bounds(): void
    {
        $validator = \Illuminate\Support\Facades\Validator::make([
            'name' => 'Over-limit percentage',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 60.0, // Exceeds platform ceiling 50%
            'max_discount_cap' => 6000.0, // Exceeds platform max cap 5000
            'service_template_ids' => [(string) Str::uuid()],
        ], FirstTimeOffer::validationRules(['discount_type' => FirstTimeOffer::TYPE_PERCENTAGE]));

        $this->assertTrue($validator->fails());
        $this->assertArrayHasKey('discount_value', $validator->errors()->messages());
        $this->assertArrayHasKey('max_discount_cap', $validator->errors()->messages());

        // Under-limit percentage (2% < 5%)
        $validatorUnder = \Illuminate\Support\Facades\Validator::make([
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 2.0,
        ], FirstTimeOffer::validationRules(['discount_type' => FirstTimeOffer::TYPE_PERCENTAGE]));
        $this->assertTrue($validatorUnder->fails());
        $this->assertArrayHasKey('discount_value', $validatorUnder->errors()->messages());

        // Flat over limit (1500 > 1000)
        $validatorFlat = \Illuminate\Support\Facades\Validator::make([
            'discount_type' => FirstTimeOffer::TYPE_FLAT,
            'discount_value' => 1500.0,
        ], FirstTimeOffer::validationRules(['discount_type' => FirstTimeOffer::TYPE_FLAT]));
        $this->assertTrue($validatorFlat->fails());
        $this->assertArrayHasKey('discount_value', $validatorFlat->errors()->messages());
    }

    // --- Helpers ---

    private function createTestUser(string $role): User
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

    private function createTestSalon(User $admin, string $name): Salon
    {
        $slug = Str::slug($name) . '-' . Str::random(5);
        return Salon::create([
            'id' => (string) Str::uuid(),
            'admin_id' => $admin->id,
            'name' => $name,
            'slug' => $slug,
            'address' => '123 Test Street',
            'submitted_by' => $admin->id,
            'status' => 'active',
        ]);
    }

    private function createTestProvider(Salon $salon): ServiceProvider
    {
        $user = $this->createTestUser('partner');
        return ServiceProvider::create([
            'id' => (string) Str::uuid(),
            'user_id' => $user->id,
            'salon_id' => $salon->id,
            'is_active' => true,
        ]);
    }
}
