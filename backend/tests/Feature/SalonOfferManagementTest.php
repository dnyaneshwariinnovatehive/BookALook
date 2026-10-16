<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\AppointmentService;
use App\Support\BillingModel;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\FirstTimeOffer;
use App\Models\PlatformPolicySetting;
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
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Str;
use Tests\TestCase;

class SalonOfferManagementTest extends TestCase
{
    use DatabaseTransactions;

    private User $adminA;
    private User $adminB;
    private User $superadmin;
    private User $customer;
    private Salon $salonA;
    private Salon $salonB;
    private ServiceCategory $category;
    private ServiceTemplate $templateA;
    private ServiceTemplate $templateB;
    private Service $serviceA;
    private Service $serviceB;
    private ServiceProvider $providerA;

    protected function setUp(): void
    {
        parent::setUp();

        $this->adminA = $this->createUser('admin');
        $this->adminB = $this->createUser('admin');
        $this->superadmin = $this->createUser('superadmin');
        $this->customer = $this->createUser('customer');

        $this->salonA = $this->createSalon($this->adminA, 'Salon Alpha');
        $this->salonB = $this->createSalon($this->adminB, 'Salon Beta');

        $this->category = ServiceCategory::firstOrCreate(
            ['name' => 'Hair Care'],
            ['id' => (string) Str::uuid(), 'is_active' => true]
        );

        $this->templateA = ServiceTemplate::create([
            'id' => (string) Str::uuid(),
            'name' => 'Haircut ' . Str::random(5),
            'category_id' => $this->category->id,
            'estimated_duration_minutes' => 30,
            'is_active' => true,
        ]);

        $this->templateB = ServiceTemplate::create([
            'id' => (string) Str::uuid(),
            'name' => 'Shave ' . Str::random(5),
            'category_id' => $this->category->id,
            'estimated_duration_minutes' => 30,
            'is_active' => true,
        ]);

        $this->serviceA = Service::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salonA->id,
            'template_id' => $this->templateA->id,
            'price' => 500.0,
            'duration_minutes' => 30,
            'advance_percentage' => 20.0,
            'is_active' => true,
        ]);

        $this->serviceB = Service::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salonA->id,
            'template_id' => $this->templateB->id,
            'price' => 300.0,
            'duration_minutes' => 30,
            'advance_percentage' => 20.0,
            'is_active' => true,
        ]);

        for ($d = 0; $d <= 6; $d++) {
            SalonWorkingHour::create([
                'salon_id' => $this->salonA->id,
                'day_of_week' => $d,
                'open_time' => '09:00:00',
                'close_time' => '19:00:00',
                'is_closed' => false,
            ]);
            SalonWorkingHour::create([
                'salon_id' => $this->salonB->id,
                'day_of_week' => $d,
                'open_time' => '09:00:00',
                'close_time' => '19:00:00',
                'is_closed' => false,
            ]);
        }

        $providerUserA = $this->createUser('provider');
        $this->providerA = ServiceProvider::create([
            'id' => (string) Str::uuid(),
            'user_id' => $providerUserA->id,
            'salon_id' => $this->salonA->id,
            'is_active' => true,
        ]);
        $this->providerA->services()->attach([$this->serviceA->id, $this->serviceB->id]);

        for ($d = 0; $d <= 6; $d++) {
            ProviderWorkingHour::create([
                'provider_id' => $this->providerA->id,
                'day_of_week' => $d,
                'shift_start' => '09:00:00',
                'shift_end' => '19:00:00',
                'is_weekly_off' => false,
            ]);
        }
    }

    public function test_1_salon_a_cannot_view_or_modify_salon_b_offers(): void
    {
        // Create an offer owned by Salon B
        $offerB = $this->createOffer([
            'salon_id' => $this->salonB->id,
            'name' => 'Salon B Special Offer',
        ], [$this->templateA->id]);

        // Salon A admin attempts to view Salon B's offer
        $response = $this->actingAs($this->adminA, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salonA->id}/offers/{$offerB->id}");
        $response->assertStatus(403);

        // Salon A admin attempts to update Salon B's offer
        $updateResponse = $this->actingAs($this->adminA, 'sanctum')
            ->putJson("/api/partner/salons/{$this->salonA->id}/offers/{$offerB->id}", [
                'name' => 'Hacked Name',
                'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
                'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
                'discount_value' => 25.0,
                'service_template_ids' => [$this->templateA->id],
            ]);
        $updateResponse->assertStatus(403);

        // Salon A admin attempts to toggle Salon B's offer
        $toggleResponse = $this->actingAs($this->adminA, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salonA->id}/offers/{$offerB->id}/toggle-active");
        $toggleResponse->assertStatus(403);

        // Salon A admin attempts to delete Salon B's offer
        $deleteResponse = $this->actingAs($this->adminA, 'sanctum')
            ->deleteJson("/api/partner/salons/{$this->salonA->id}/offers/{$offerB->id}");
        $deleteResponse->assertStatus(403);

        // Verify Salon B offer is unchanged
        $this->assertSame('Salon B Special Offer', $offerB->fresh()->name);
    }

    public function test_2_salon_admin_cannot_modify_superadmin_platform_offers(): void
    {
        // SuperAdmin platform offer (salon_id = null)
        $platformOffer = $this->createOffer([
            'salon_id' => null,
            'name' => 'Platform Wide Welcome Offer',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
        ], [$this->templateA->id]);

        // Salon A admin tries to update platform offer
        $response = $this->actingAs($this->adminA, 'sanctum')
            ->putJson("/api/partner/salons/{$this->salonA->id}/offers/{$platformOffer->id}", [
                'name' => 'Hijacked Platform Offer',
                'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
                'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
                'discount_value' => 20.0,
                'service_template_ids' => [$this->templateA->id],
            ]);
        $response->assertStatus(403);
    }

    public function test_3_authorized_salon_admin_can_create_edit_activate_and_deactivate_own_offer(): void
    {
        // 1. Fetch options
        $optionsRes = $this->actingAs($this->adminA, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salonA->id}/offers/options");
        $optionsRes->assertStatus(200);
        $optionsRes->assertJsonStructure([
            'success',
            'data' => [
                'services',
                'scopes',
                'discount_types',
                'policy',
            ],
        ]);

        // 2. Create offer for Salon A
        $createRes = $this->actingAs($this->adminA, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salonA->id}/offers", [
                'name' => 'Salon Alpha Grand Opening',
                'description' => '20% off for first-time visitors',
                'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
                'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
                'discount_value' => 20.0,
                'max_discount_cap' => 150.0,
                'service_template_ids' => [$this->templateA->id],
                'is_active' => true,
            ]);
        $createRes->assertStatus(201);
        $offerId = $createRes->json('data.id');
        $this->assertNotNull($offerId);

        $offer = FirstTimeOffer::findOrFail($offerId);
        $this->assertSame($this->salonA->id, $offer->salon_id);
        $this->assertTrue($offer->is_active);

        // 3. List offers for Salon A
        $listRes = $this->actingAs($this->adminA, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salonA->id}/offers");
        $listRes->assertStatus(200);
        $this->assertCount(1, $listRes->json('data'));
        $this->assertSame('Salon Alpha Grand Opening', $listRes->json('data.0.name'));
        $this->assertSame('Active', $listRes->json('data.0.status_label'));

        // 4. Edit offer
        $editRes = $this->actingAs($this->adminA, 'sanctum')
            ->putJson("/api/partner/salons/{$this->salonA->id}/offers/{$offerId}", [
                'name' => 'Salon Alpha Revised Opening',
                'description' => '25% off haircut and shave',
                'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
                'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
                'discount_value' => 25.0,
                'max_discount_cap' => 200.0,
                'service_template_ids' => [$this->templateA->id, $this->templateB->id],
                'is_active' => true,
            ]);
        $editRes->assertStatus(200);
        $this->assertSame('Salon Alpha Revised Opening', $offer->fresh()->name);
        $this->assertEquals(25.0, (float) $offer->fresh()->discount_value);
        $this->assertCount(2, $offer->fresh()->serviceTemplates);

        // 5. Deactivate offer
        $toggleRes = $this->actingAs($this->adminA, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salonA->id}/offers/{$offerId}/toggle-active", [
                'is_active' => false,
            ]);
        $toggleRes->assertStatus(200);
        $this->assertFalse($offer->fresh()->is_active);
        $this->assertSame('Inactive', $toggleRes->json('data.status_label'));

        // 6. Reactivate offer
        $toggleRes2 = $this->actingAs($this->adminA, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salonA->id}/offers/{$offerId}/toggle-active", [
                'is_active' => true,
            ]);
        $toggleRes2->assertStatus(200);
        $this->assertTrue($offer->fresh()->is_active);
        $this->assertSame('Active', $toggleRes2->json('data.status_label'));
    }

    public function test_4_first_time_eligibility_follows_configured_scope(): void
    {
        // Offer 1: new_to_platform owned by Salon A
        $platformScopeOffer = $this->createOffer([
            'salon_id' => $this->salonA->id,
            'name' => 'Platform Scope Offer',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            'max_discount_cap' => 200.0,
        ], [$this->templateA->id]);

        // Customer has a prior completed booking at Salon B
        Appointment::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salonB->id,
            'customer_id' => $this->customer->id,
            'appointed_provider_id' => $this->providerA->id,
            'customer_phone_hash' => FirstTimeOffer::hashPhone($this->customer->phone),
            'status' => 'completed',
            'appointment_date' => Carbon::yesterday()->toDateString(),
            'start_time' => '10:00:00',
            'end_time' => '10:30:00',
            'total_amount' => 500.0,
            'advance_amount' => 100.0,
            'balance_amount' => 400.0,
        ]);

        // Customer attempts to book at Salon A with platformScopeOffer -> Ineligible because customer has prior booking on platform
        $this->createCart($this->customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $res = $this->actingAs($this->customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
                'first_time_offer_id' => $platformScopeOffer->id,
            ]
        );
        $res->assertStatus(201);
        $app = Appointment::findOrFail($res->json('appointment.id'));
        $this->assertNull($app->first_time_offer_id);
        $this->assertEquals(0, (float) $app->first_time_discount_amount);

        // Now test new_to_salon offer: Customer has no prior booking at Salon A!
        $salonScopeOffer = $this->createOffer([
            'salon_id' => $this->salonA->id,
            'name' => 'Salon Scope Offer',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            'max_discount_cap' => 200.0,
        ], [$this->templateA->id]);

        $this->createCart($this->customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $res2 = $this->actingAs($this->customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '11:00',
                'provider_id' => $this->providerA->id,
                'first_time_offer_id' => $salonScopeOffer->id,
            ]
        );
        $res2->assertStatus(201);
        $app2 = Appointment::findOrFail($res2->json('appointment.id'));
        // Customer IS eligible for new_to_salon offer at Salon A!
        $this->assertSame($salonScopeOffer->id, $app2->first_time_offer_id);
        $this->assertEquals(100.0, (float) $app2->first_time_discount_amount);
    }

    public function test_5_cancelled_previous_booking_counts_toward_eligibility(): void
    {
        $offer = $this->createOffer([
            'salon_id' => $this->salonA->id,
            'name' => 'Salon A First Timer',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
            'discount_type' => FirstTimeOffer::TYPE_FLAT,
            'discount_value' => 100.0,
            'max_discount_cap' => 100.0,
        ], [$this->templateA->id]);

        // Prior booking cancelled by customer
        Appointment::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salonA->id,
            'customer_id' => $this->customer->id,
            'appointed_provider_id' => $this->providerA->id,
            'customer_phone_hash' => FirstTimeOffer::hashPhone($this->customer->phone),
            'status' => 'cancelled',
            'cancelled_by' => 'customer',
            'appointment_date' => Carbon::yesterday()->toDateString(),
            'start_time' => '10:00:00',
            'end_time' => '10:30:00',
            'total_amount' => 500.0,
            'advance_amount' => 100.0,
            'balance_amount' => 400.0,
        ]);

        // Booking at Salon A should NOT receive first-time offer because cancelled booking counts
        $this->createCart($this->customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $res = $this->actingAs($this->customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
                'first_time_offer_id' => $offer->id,
            ]
        );
        $res->assertStatus(201);
        $app = Appointment::findOrFail($res->json('appointment.id'));
        $this->assertNull($app->first_time_offer_id);
        $this->assertEquals(0, (float) $app->first_time_discount_amount);
    }

    public function test_6_only_selected_eligible_services_receive_discount(): void
    {
        // Offer only targets templateA (serviceA), NOT templateB (serviceB)
        $offer = $this->createOffer([
            'salon_id' => $this->salonA->id,
            'name' => 'Haircut Only Discount',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            'max_discount_cap' => 200.0,
        ], [$this->templateA->id]);

        // Cart with both serviceA (500) and serviceB (300)
        $this->createCart($this->customer, $this->salonA, [
            ['service' => $this->serviceA, 'qty' => 1],
            ['service' => $this->serviceB, 'qty' => 1],
        ]);

        $res = $this->actingAs($this->customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
                'first_time_offer_id' => $offer->id,
            ]
        );
        $res->assertStatus(201);
        $app = Appointment::findOrFail($res->json('appointment.id'));

        // Total subtotal 800. Discount should be 20% of 500 = 100, serviceB gets 0
        $this->assertEquals(100.0, (float) $app->first_time_discount_amount);
        $this->assertEquals(700.0, (float) $app->total_amount);

        $lineA = AppointmentService::where('appointment_id', $app->id)
            ->where('service_id', $this->serviceA->id)
            ->first();
        $lineB = AppointmentService::where('appointment_id', $app->id)
            ->where('service_id', $this->serviceB->id)
            ->first();

        $this->assertEquals(100.0, (float) $lineA->first_time_discount_amount);
        $this->assertEquals(0.0, (float) $lineB->first_time_discount_amount);
    }

    public function test_7_appointment_details_partner_endpoint_returns_persisted_offer_and_snapshot(): void
    {
        $offer = $this->createOffer([
            'salon_id' => $this->salonA->id,
            'name' => 'Special Salon Welcome',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
        ], [$this->templateA->id]);

        $this->createCart($this->customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $res = $this->actingAs($this->customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
                'first_time_offer_id' => $offer->id,
            ]
        );
        $appointmentId = $res->json('appointment.id');
        $appointment = Appointment::findOrFail($appointmentId);
        $appointment->update(['status' => 'scheduled']);

        // Check Partner Appointments API
        $partnerRes = $this->actingAs($this->adminA, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salonA->id}/appointments");
        $partnerRes->assertStatus(200);

        $bookingData = collect($partnerRes->json('appointments'))->firstWhere('id', $appointmentId);
        $this->assertNotNull($bookingData);
        $this->assertSame('Special Salon Welcome', $bookingData['first_time_offer']['name']);
        $this->assertEquals(100.0, (float) $bookingData['first_time_discount_amount']);
        $this->assertEquals(100.0, (float) $bookingData['services'][0]['first_time_discount_amount']);
        $this->assertEquals(500.0, (float) $bookingData['services'][0]['price_at_booking']);
        $this->assertEquals(500.0, (float) $bookingData['services'][0]['original_service_price']);
    }

    public function test_8_legacy_and_no_offer_appointments_render_normally(): void
    {
        // Legacy booking with null first_time_offer_id and 0 discount
        $legacyApp = Appointment::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salonA->id,
            'customer_id' => $this->customer->id,
            'appointed_provider_id' => $this->providerA->id,
            'status' => 'scheduled',
            'appointment_date' => Carbon::tomorrow()->toDateString(),
            'start_time' => '14:00:00',
            'end_time' => '14:30:00',
            'total_amount' => 500.0,
            'advance_amount' => 100.0,
            'balance_amount' => 400.0,
            'first_time_offer_id' => null,
            'first_time_discount_amount' => 0.0,
        ]);

        AppointmentService::create([
            'id' => (string) Str::uuid(),
            'appointment_id' => $legacyApp->id,
            'service_id' => $this->serviceA->id,
            'price_at_booking' => 500.0,
            'original_service_price' => 500.0,
            'first_time_discount_amount' => 0.0,
            'duration_minutes_at_booking' => 30,
        ]);

        $partnerRes = $this->actingAs($this->adminA, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salonA->id}/appointments");
        $partnerRes->assertStatus(200);

        $bookingData = collect($partnerRes->json('appointments'))->firstWhere('id', $legacyApp->id);
        $this->assertNotNull($bookingData);
        $this->assertNull($bookingData['first_time_offer']);
        $this->assertEquals(0, (float) $bookingData['first_time_discount_amount']);
    }

    public function test_9_subsequent_offer_edit_or_deactivation_does_not_alter_historical_booking(): void
    {
        $offer = $this->createOffer([
            'salon_id' => $this->salonA->id,
            'name' => 'Original Offer Name',
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
        ], [$this->templateA->id]);

        $this->createCart($this->customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $res = $this->actingAs($this->customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
                'first_time_offer_id' => $offer->id,
            ]
        );
        $appointmentId = $res->json('appointment.id');
        $appointment = Appointment::findOrFail($appointmentId);
        $appointment->update(['status' => 'scheduled']);

        // Now admin updates offer value to 50% and deactivates it
        $this->actingAs($this->adminA, 'sanctum')
            ->putJson("/api/partner/salons/{$this->salonA->id}/offers/{$offer->id}", [
                'name' => 'Changed Offer Name',
                'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
                'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
                'discount_value' => 50.0,
                'service_template_ids' => [$this->templateA->id],
                'is_active' => false,
            ])->assertStatus(200);

        // Fetch partner appointment details
        $partnerRes = $this->actingAs($this->adminA, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salonA->id}/appointments");
        $partnerRes->assertStatus(200);

        $bookingData = collect($partnerRes->json('appointments'))->firstWhere('id', $appointmentId);

        // Historical discount remains exactly 100.0, total remains 400.0
        $this->assertEquals(100.0, (float) $bookingData['first_time_discount_amount']);
        $this->assertEquals(400.0, (float) $bookingData['total_amount']);
        $this->assertEquals(100.0, (float) $bookingData['services'][0]['first_time_discount_amount']);
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
        $salon = Salon::create([
            'id' => (string) Str::uuid(),
            'admin_id' => $admin->id,
            'name' => $name,
            'slug' => $slug,
            'address' => '123 Test Ave',
            'submitted_by' => $admin->id,
            'status' => 'active',
        ]);

        $plan = SubscriptionPlan::firstOrCreate(
            ['name' => 'Partner Pro Test'],
            [
                'id' => (string) Str::uuid(),
                'price' => 999,
                'is_active' => true,
            ]
        );

        SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'billing_type' => BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => $plan->price,
            'start_date' => Carbon::today()->subDays(10),
            'end_date' => Carbon::today()->addDays(30),
            'status' => 'active',
        ]);

        return $salon;
    }

    private function createOffer(array $overrides = [], array $templateIds = []): FirstTimeOffer
    {
        $offer = FirstTimeOffer::create(array_merge([
            'name' => 'Offer ' . Str::random(5),
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            'max_discount_cap' => 500.0,
            'is_active' => true,
        ], $overrides));

        if (! empty($templateIds)) {
            $offer->serviceTemplates()->sync($templateIds);
        }

        if ($offer->salon_id) {
            $offer->participatingSalons()->sync([$offer->salon_id]);
        }

        return $offer;
    }

    private function createCart(User $customer, Salon $salon, array $lines): Cart
    {
        Cart::where('customer_id', $customer->id)->where('status', 'active')->delete();

        $cart = Cart::create([
            'id' => (string) Str::uuid(),
            'customer_id' => $customer->id,
            'salon_id' => $salon->id,
            'status' => 'active',
        ]);

        foreach ($lines as $line) {
            CartItem::create([
                'id' => (string) Str::uuid(),
                'cart_id' => $cart->id,
                'service_id' => $line['service']->id,
                'quantity' => $line['qty'] ?? 1,
            ]);
        }

        return $cart;
    }
}
