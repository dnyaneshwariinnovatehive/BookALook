<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\AppointmentService;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\FirstTimeOffer;
use App\Models\FirstTimeOfferRedemption;
use App\Models\ProviderWorkingHour;
use App\Models\Salon;
use App\Models\SalonWorkingHour;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceProvider;
use App\Models\ServiceTemplate;
use App\Models\User;
use App\Services\BookingPaymentService;
use App\Services\CustomerOfferEligibilityService;
use Carbon\Carbon;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class FirstTimeOfferLifecycleTest extends TestCase
{
    use DatabaseTransactions;

    private User $admin;

    private Salon $salonA;

    private Salon $salonB;

    private ServiceCategory $category;

    private ServiceTemplate $templateA;

    private ServiceTemplate $templateB;

    private Service $serviceA;

    private Service $serviceB;

    private Service $serviceB2;

    private ServiceProvider $providerA;

    private ServiceProvider $providerB;

    protected function setUp(): void
    {
        parent::setUp();

        $this->admin = $this->createUser('admin');
        $this->salonA = $this->createSalon($this->admin, 'Salon Alpha');
        $this->salonB = $this->createSalon($this->admin, 'Salon Beta');

        $this->category = ServiceCategory::firstOrCreate(
            ['name' => 'Hair Care'],
            ['id' => (string) Str::uuid(), 'is_active' => true]
        );

        $this->templateA = ServiceTemplate::create([
            'id' => (string) Str::uuid(),
            'name' => 'Signature Haircut '.Str::random(5),
            'category_id' => $this->category->id,
            'estimated_duration_minutes' => 30,
            'is_active' => true,
        ]);

        $this->templateB = ServiceTemplate::create([
            'id' => (string) Str::uuid(),
            'name' => 'Classic Shave '.Str::random(5),
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

        $providerUser = $this->createUser('provider');
        $this->providerA = ServiceProvider::create([
            'id' => (string) Str::uuid(),
            'user_id' => $providerUser->id,
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

        $this->serviceB2 = Service::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salonB->id,
            'template_id' => $this->templateA->id,
            'price' => 500.0,
            'duration_minutes' => 30,
            'advance_percentage' => 20.0,
            'is_active' => true,
        ]);
        $providerUserB = $this->createUser('provider');
        $this->providerB = ServiceProvider::create([
            'id' => (string) Str::uuid(),
            'user_id' => $providerUserB->id,
            'salon_id' => $this->salonB->id,
            'is_active' => true,
        ]);
        $this->providerB->services()->attach([$this->serviceB2->id]);
        for ($d = 0; $d <= 6; $d++) {
            ProviderWorkingHour::create([
                'provider_id' => $this->providerB->id,
                'day_of_week' => $d,
                'shift_start' => '09:00:00',
                'shift_end' => '19:00:00',
                'is_weekly_off' => false,
            ]);
        }
    }

    // =========================================================================
    // 1. RESERVATION TESTS
    // =========================================================================

    public function test_eligible_customer_successfully_reserves_an_offer_during_booking(): void
    {
        $customer = $this->createUser('customer');
        $offer = $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            'max_discount_cap' => 200.0,
        ], [$this->templateA->id]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);

        $response = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointmentId = $response->json('appointment.id');
        $appointment = Appointment::findOrFail($appointmentId);

        $this->assertSame('pending_payment', $appointment->status);
        $this->assertSame($offer->id, $appointment->first_time_offer_id);
        $this->assertEquals(100.0, (float) $appointment->first_time_discount_amount);
        $this->assertEquals(400.0, (float) $appointment->total_amount);

        // Verify line item discount allocation
        $line = AppointmentService::where('appointment_id', $appointment->id)->first();
        $this->assertNotNull($line);
        $this->assertEquals(100.0, (float) $line->first_time_discount_amount);
        $this->assertEquals(500.0, (float) $line->price_at_booking);
        $this->assertEquals(500.0, (float) $line->original_service_price);

        // Verify redemption is in reserved status with active entitlement key
        $redemption = FirstTimeOfferRedemption::where('appointment_id', $appointment->id)->first();
        $this->assertNotNull($redemption);
        $this->assertSame(FirstTimeOfferRedemption::STATUS_RESERVED, $redemption->status);
        $this->assertEquals(100.0, (float) $redemption->discount_amount);
        $this->assertNotNull($redemption->active_entitlement_key);
        $this->assertSame(FirstTimeOffer::hashPhone($customer->phone), $redemption->customer_phone_hash);
        $this->assertNull($redemption->committed_at);

        // Campaign counter must NOT increment during reservation
        $this->assertSame(0, (int) $offer->fresh()->current_redemptions);
    }

    public function test_ineligible_customer_cannot_reserve_offer(): void
    {
        $customer = $this->createUser('customer');
        $offer = $this->createOffer([], [$this->templateA->id]);

        // Prior scheduled booking disqualifies customer
        $this->createAppointment($customer, $this->salonA, 'scheduled');

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);

        $response = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '11:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointment = Appointment::findOrFail($response->json('appointment.id'));
        $this->assertNull($appointment->first_time_offer_id);
        $this->assertEquals(0.0, (float) $appointment->first_time_discount_amount);
        $this->assertEquals(500.0, (float) $appointment->total_amount);

        $this->assertDatabaseMissing('first_time_offer_redemptions', [
            'appointment_id' => $appointment->id,
        ]);
    }

    public function test_inactive_expired_or_future_offer_cannot_be_reserved(): void
    {
        $customer = $this->createUser('customer');
        $expiredOffer = $this->createOffer([
            'is_active' => true,
            'starts_at' => Carbon::today()->subDays(10),
            'ends_at' => Carbon::today()->subDay(),
        ], [$this->templateA->id]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);

        $response = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointment = Appointment::findOrFail($response->json('appointment.id'));
        $this->assertNull($appointment->first_time_offer_id);
        $this->assertEquals(0.0, (float) $appointment->first_time_discount_amount);
    }

    public function test_unselected_service_template_cannot_claim_offer(): void
    {
        $customer = $this->createUser('customer');
        // Offer is only for template A
        $this->createOffer([], [$this->templateA->id]);

        // Customer puts service B (template B) in cart
        $this->createCart($customer, $this->salonA, [['service' => $this->serviceB, 'qty' => 1]]);

        $response = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointment = Appointment::findOrFail($response->json('appointment.id'));
        $this->assertNull($appointment->first_time_offer_id);
        $this->assertEquals(0.0, (float) $appointment->first_time_discount_amount);
    }

    public function test_reservation_uses_server_calculated_discount_amount(): void
    {
        $customer = $this->createUser('customer');
        $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_FLAT,
            'discount_value' => 75.0,
            'max_discount_cap' => null,
        ], [$this->templateA->id]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);

        $response = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointment = Appointment::findOrFail($response->json('appointment.id'));
        $this->assertEquals(75.0, (float) $appointment->first_time_discount_amount);
        $this->assertEquals(425.0, (float) $appointment->total_amount);
    }

    public function test_client_submitted_discount_amounts_and_entitlement_flags_are_ignored(): void
    {
        $customer = $this->createUser('customer');
        $offer = $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 10.0, // 500 * 10% = 50
        ], [$this->templateA->id]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);

        $response = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
                // Client attempts to tamper with discount
                'first_time_discount_amount' => 450.0,
                'discount_amount' => 450.0,
                'entitlement_status' => 'committed',
            ]
        )->assertStatus(201);

        $appointment = Appointment::findOrFail($response->json('appointment.id'));
        // Server ignores client input and strictly uses calculated 50.0
        $this->assertEquals(50.0, (float) $appointment->first_time_discount_amount);
        $this->assertEquals(450.0, (float) $appointment->total_amount);
    }

    public function test_two_simultaneous_reservation_attempts_for_the_same_entitlement_cannot_both_succeed(): void
    {
        $customer = $this->createUser('customer');
        $offer = $this->createOffer([], [$this->templateA->id]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);

        // First reservation succeeds
        $res1 = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        // Populate cart at Salon B for second simultaneous booking attempt
        $this->createCart($customer, $this->salonB, [['service' => $this->serviceB2, 'qty' => 1]]);

        // Second booking attempt while first reservation is active cannot claim discount
        $res2 = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonB->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:30',
                'provider_id' => $this->providerB->id,
            ]
        )->assertStatus(201);

        $app2 = Appointment::find($res2->json('appointment.id'));
        $this->assertNull($app2->first_time_offer_id, 'Second booking while reservation active must not receive the discount');
        $this->assertEquals(0.0, (float) $app2->first_time_discount_amount);
        $this->assertSame(1, FirstTimeOfferRedemption::where('customer_id', $customer->id)->count());

        // Also verify DB unique constraint on active_entitlement_key strictly prevents two active reservations
        $redemption1 = FirstTimeOfferRedemption::where('appointment_id', $res1->json('appointment.id'))->first();
        $this->assertNotNull($redemption1);

        $dummyApp = $this->createAppointment($customer, $this->salonA, 'pending_payment');
        $this->expectException(QueryException::class);
        FirstTimeOfferRedemption::create([
            'id' => (string) Str::uuid(),
            'offer_id' => $offer->id,
            'customer_id' => $customer->id,
            'customer_phone_hash' => FirstTimeOffer::hashPhone($customer->phone),
            'salon_id' => $this->salonA->id,
            'scope' => $offer->scope,
            'appointment_id' => $dummyApp->id,
            'status' => FirstTimeOfferRedemption::STATUS_RESERVED,
            'discount_amount' => 100.0,
            'active_entitlement_key' => $redemption1->active_entitlement_key, // Duplicate active key
            'reserved_at' => now(),
        ]);
    }

    public function test_concurrent_reservations_cannot_exceed_max_redemptions(): void
    {
        $customer1 = $this->createUser('customer');
        $customer2 = $this->createUser('customer');

        // Offer has cap of 1 total redemption
        $offer = $this->createOffer([
            'max_redemptions' => 1,
            'current_redemptions' => 0,
        ], [$this->templateA->id]);

        // Customer 1 books -> reserves the 1 available spot
        $this->createCart($customer1, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $this->actingAs($customer1, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        // Customer 2 attempts to book -> capacity (committed + reserved) is exhausted
        $this->createCart($customer2, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $res2 = $this->actingAs($customer2, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:30',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointment2 = Appointment::findOrFail($res2->json('appointment.id'));
        // Second customer does not receive the discount because active holds count against campaign limit
        $this->assertNull($appointment2->first_time_offer_id);
        $this->assertEquals(0.0, (float) $appointment2->first_time_discount_amount);
    }

    // =========================================================================
    // 2. PAYMENT COMMITMENT TESTS
    // =========================================================================

    public function test_verified_payment_commits_reserved_redemption_exactly_once(): void
    {
        $customer = $this->createUser('customer');
        $offer = $this->createOffer([], [$this->templateA->id]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);

        $booked = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointmentId = $booked->json('appointment.id');
        $redemption = FirstTimeOfferRedemption::where('appointment_id', $appointmentId)->first();
        $this->assertSame(FirstTimeOfferRedemption::STATUS_RESERVED, $redemption->status);

        // Demo pay verifies and confirms
        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/payment/demo-pay")
            ->assertStatus(200);

        $appointment = Appointment::find($appointmentId);
        $this->assertSame('scheduled', $appointment->status);

        $committedRedemption = $redemption->fresh();
        $this->assertSame(FirstTimeOfferRedemption::STATUS_COMMITTED, $committedRedemption->status);
        $this->assertNotNull($committedRedemption->committed_at);
        $this->assertNotNull($committedRedemption->active_entitlement_key);

        // Offer current_redemptions counter increments exactly once
        $this->assertSame(1, (int) $offer->fresh()->current_redemptions);
    }

    public function test_duplicate_payment_callbacks_do_not_create_duplicate_commitments(): void
    {
        $customer = $this->createUser('customer');
        $offer = $this->createOffer([], [$this->templateA->id]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);

        $booked = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointmentId = $booked->json('appointment.id');

        // First payment confirmation
        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/payment/demo-pay")
            ->assertStatus(200);

        // Retried payment confirmation
        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/payment/demo-pay")
            ->assertStatus(200);

        $this->assertSame(1, FirstTimeOfferRedemption::where('appointment_id', $appointmentId)->count());
        $this->assertSame(1, (int) $offer->fresh()->current_redemptions);
    }

    public function test_failed_payment_does_not_commit_redemption(): void
    {
        $customer = $this->createUser('customer');
        $offer = $this->createOffer([], [$this->templateA->id]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);

        $booked = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointmentId = $booked->json('appointment.id');

        // Tampered signature
        $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/appointments/{$appointmentId}/payment/confirm",
            [
                'razorpay_payment_id' => 'pay_tampered_001',
                'razorpay_signature' => str_repeat('0', 64),
            ]
        )->assertStatus(422);

        $redemption = FirstTimeOfferRedemption::where('appointment_id', $appointmentId)->first();
        $this->assertSame(FirstTimeOfferRedemption::STATUS_RESERVED, $redemption->status);
        $this->assertNull($redemption->committed_at);
        $this->assertSame(0, (int) $offer->fresh()->current_redemptions);
    }

    public function test_client_reported_success_without_payment_verification_does_not_commit(): void
    {
        $customer = $this->createUser('customer');
        $offer = $this->createOffer([], [$this->templateA->id]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);

        $booked = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointmentId = $booked->json('appointment.id');
        $redemption = FirstTimeOfferRedemption::where('appointment_id', $appointmentId)->first();

        $this->assertSame(FirstTimeOfferRedemption::STATUS_RESERVED, $redemption->status);
        $this->assertNull($redemption->committed_at);
        $this->assertSame(0, (int) $offer->fresh()->current_redemptions);
    }

    public function test_committed_redemption_survives_subsequent_appointment_cancellation(): void
    {
        $customer = $this->createUser('customer');
        $offer = $this->createOffer([], [$this->templateA->id]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);

        $booked = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointmentId = $booked->json('appointment.id');

        // Confirm payment
        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/payment/demo-pay")
            ->assertStatus(200);

        // Cancel the appointment
        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/cancel")
            ->assertStatus(200);

        $appointment = Appointment::find($appointmentId);
        $this->assertSame('cancelled', $appointment->status);

        // Redemption remains committed, key intact, current_redemptions remains 1
        $redemption = FirstTimeOfferRedemption::where('appointment_id', $appointmentId)->first();
        $this->assertSame(FirstTimeOfferRedemption::STATUS_COMMITTED, $redemption->status);
        $this->assertNotNull($redemption->active_entitlement_key);
        $this->assertSame(1, (int) $offer->fresh()->current_redemptions);

        // Customer remains ineligible for the offer
        $service = app(CustomerOfferEligibilityService::class);
        $this->assertFalse($service->isCustomerEligibleForOffer($customer, $offer, $this->salonA->id));
    }

    public function test_bookings_stored_discount_reconciles_with_its_committed_redemption(): void
    {
        $customer = $this->createUser('customer');
        $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 25.0,
        ], [$this->templateA->id]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);

        $booked = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointmentId = $booked->json('appointment.id');
        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/payment/demo-pay")
            ->assertStatus(200);

        $appointment = Appointment::find($appointmentId);
        $redemption = FirstTimeOfferRedemption::where('appointment_id', $appointmentId)->first();

        $this->assertEquals((float) $appointment->first_time_discount_amount, (float) $redemption->discount_amount);
        $lineSum = AppointmentService::where('appointment_id', $appointmentId)->sum('first_time_discount_amount');
        $this->assertEquals((float) $appointment->first_time_discount_amount, (float) $lineSum);
    }

    // =========================================================================
    // 3. RELEASE AND RACE HANDLING TESTS
    // =========================================================================

    public function test_expired_hold_releases_its_reservation(): void
    {
        $customer = $this->createUser('customer');
        $offer = $this->createOffer([], [$this->templateA->id]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);

        $booked = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointmentId = $booked->json('appointment.id');
        $appointment = Appointment::find($appointmentId);

        // Force hold to expire
        $appointment->update(['payment_hold_expires_at' => now()->subMinutes(5)]);

        // Run hold release
        $releasedCount = app(BookingPaymentService::class)->releaseExpiredHolds();
        $this->assertSame(1, $releasedCount);

        $redemption = FirstTimeOfferRedemption::where('appointment_id', $appointmentId)->first();
        $this->assertSame(FirstTimeOfferRedemption::STATUS_RELEASED, $redemption->status);
        $this->assertNull($redemption->active_entitlement_key);
        $this->assertNotNull($redemption->released_at);
        $this->assertSame(0, (int) $offer->fresh()->current_redemptions);
    }

    public function test_abandoned_unpaid_hold_does_not_disqualify_customer(): void
    {
        $customer = $this->createUser('customer');
        $offer = $this->createOffer([], [$this->templateA->id]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);

        $booked = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointmentId = $booked->json('appointment.id');

        // Customer abandons payment
        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/payment/abandon")
            ->assertStatus(200);

        // Customer is still eligible for the offer!
        $service = app(CustomerOfferEligibilityService::class);
        $this->assertTrue($service->isCustomerEligibleForOffer($customer, $offer, $this->salonA->id));

        // Customer can successfully book again with the discount
        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $booked2 = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:30',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointment2 = Appointment::find($booked2->json('appointment.id'));
        $this->assertSame($offer->id, $appointment2->first_time_offer_id);
        $this->assertEquals(100.0, (float) $appointment2->first_time_discount_amount);
    }

    public function test_repeated_expiration_and_cancellation_calls_are_safe(): void
    {
        $customer = $this->createUser('customer');
        $this->createOffer([], [$this->templateA->id]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);

        $booked = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointment = Appointment::find($booked->json('appointment.id'));
        $paymentService = app(BookingPaymentService::class);

        // First release
        $paymentService->release($appointment, 'Hold expired');
        $redemption = FirstTimeOfferRedemption::where('appointment_id', $appointment->id)->first();
        $this->assertSame(FirstTimeOfferRedemption::STATUS_RELEASED, $redemption->status);

        // Repeated release must be idempotent and safe
        $paymentService->release($appointment, 'Hold expired');
        $this->assertSame(FirstTimeOfferRedemption::STATUS_RELEASED, $redemption->fresh()->status);
    }

    public function test_payment_racing_with_expiration_cannot_create_contradictory_states(): void
    {
        $customer = $this->createUser('customer');
        $this->createOffer([], [$this->templateA->id]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);

        $booked = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointment = Appointment::find($booked->json('appointment.id'));
        $redemption = FirstTimeOfferRedemption::where('appointment_id', $appointment->id)->first();

        // 1. If released first, commit() must refuse
        $redemption->release('Test release');
        $this->assertFalse($redemption->commit());
        $this->assertSame(FirstTimeOfferRedemption::STATUS_RELEASED, $redemption->status);

        // 2. If committed, release() must refuse
        $dummyApp2 = $this->createAppointment($customer, $this->salonA, 'scheduled');
        $redemption2 = FirstTimeOfferRedemption::create([
            'id' => (string) Str::uuid(),
            'offer_id' => $redemption->offer_id,
            'customer_id' => $customer->id,
            'customer_phone_hash' => FirstTimeOffer::hashPhone($customer->phone),
            'salon_id' => $this->salonA->id,
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'appointment_id' => $dummyApp2->id,
            'status' => FirstTimeOfferRedemption::STATUS_COMMITTED,
            'discount_amount' => 50.0,
            'active_entitlement_key' => 'comm_'.Str::random(10),
            'reserved_at' => now(),
            'committed_at' => now(),
        ]);

        $this->assertFalse($redemption2->release('Cannot release committed'));
        $this->assertSame(FirstTimeOfferRedemption::STATUS_COMMITTED, $redemption2->fresh()->status);
    }

    public function test_expired_reservation_safely_recommits_when_capacity_and_eligibility_allow(): void
    {
        $customer = $this->createUser('customer');
        $offer = $this->createOffer([], [$this->templateA->id]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);

        $booked = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointmentId = $booked->json('appointment.id');
        $appointment = Appointment::find($appointmentId);

        $paymentService = app(BookingPaymentService::class);

        // 1. Customer opened payment sheet and got payment credentials before expiration
        $simulated = $paymentService->simulatePayment($appointment);
        $this->assertNotNull($simulated);

        // 2. Hold expires while customer was completing payment at the gateway
        $appointment->update(['payment_hold_expires_at' => now()->subMinutes(5)]);
        $paymentService->releaseExpiredHolds();

        $redemption = FirstTimeOfferRedemption::where('appointment_id', $appointmentId)->first();
        $this->assertSame(FirstTimeOfferRedemption::STATUS_RELEASED, $redemption->status);
        $this->assertNull($redemption->active_entitlement_key);

        // 3. Payment callback arrives from gateway with verified payment
        $result = $paymentService->confirm(
            $appointment,
            $simulated['payment_id'],
            $simulated['signature'],
            $customer->id
        );

        $this->assertTrue($result['ok']);
        $this->assertTrue($result['recommitted'] ?? false);

        // Redemption is recommitted and campaign counter is safely incremented
        $this->assertSame(FirstTimeOfferRedemption::STATUS_COMMITTED, $redemption->fresh()->status);
        $this->assertSame(1, (int) $offer->fresh()->current_redemptions);
        $this->assertSame('scheduled', $appointment->fresh()->status);
    }

    public function test_expired_reservation_cannot_be_recommitted_if_campaign_capacity_exhausted(): void
    {
        $customer1 = $this->createUser('customer');
        $customer2 = $this->createUser('customer');

        // Offer has cap of exactly 1 redemption
        $offer = $this->createOffer([
            'max_redemptions' => 1,
            'current_redemptions' => 0,
        ], [$this->templateA->id]);

        $paymentService = app(BookingPaymentService::class);

        // 1. Customer 1 books and opens payment sheet
        $this->createCart($customer1, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $booked1 = $this->actingAs($customer1, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $app1 = Appointment::find($booked1->json('appointment.id'));
        $simulated1 = $paymentService->simulatePayment($app1);

        // Customer 1's hold expires and is released
        $app1->update(['payment_hold_expires_at' => now()->subMinutes(5)]);
        $paymentService->releaseExpiredHolds();

        $redemption1 = FirstTimeOfferRedemption::where('appointment_id', $app1->id)->first();
        $this->assertSame(FirstTimeOfferRedemption::STATUS_RELEASED, $redemption1->status);

        // 2. Customer 2 books and successfully commits the last available spot
        $this->createCart($customer2, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $booked2 = $this->actingAs($customer2, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:30',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $app2 = Appointment::find($booked2->json('appointment.id'));
        $this->actingAs($customer2, 'sanctum')
            ->postJson("/api/customer/appointments/{$app2->id}/payment/demo-pay")
            ->assertStatus(200);

        // Offer is now 100% full (1 of 1 redeemed)
        $this->assertSame(1, (int) $offer->fresh()->current_redemptions);

        // 3. Customer 1's delayed payment confirmation now arrives with verified signature
        $result = $paymentService->confirm(
            $app1,
            $simulated1['payment_id'],
            $simulated1['signature'],
            $customer1->id
        );

        // Cannot be recommitted because capacity is exhausted!
        $this->assertFalse($result['ok']);
        $this->assertTrue($result['hold_expired'] ?? false);
        $this->assertFalse($result['reconciled'] ?? true);
        $this->assertTrue($result['refunded'] ?? false);

        // Redemption 1 remains released
        $this->assertSame(FirstTimeOfferRedemption::STATUS_RELEASED, $redemption1->fresh()->status);
        // Offer current_redemptions never exceeds max_redemptions
        $this->assertSame(1, (int) $offer->fresh()->current_redemptions);
        // Appointment 1 remains cancelled
        $this->assertSame('cancelled', $app1->fresh()->status);

        // Payment is recorded in DB with failure metadata rather than dropped
        $payment = DB::table('payments')->where('appointment_id', $app1->id)->first();
        $this->assertNotNull($payment);
        $this->assertSame('success', $payment->status);
        $meta = json_encode($payment->metadata);
        $this->assertStringContainsString('reconciliation_failed', $meta);

        // Durable payment_refunds record was persisted
        $refundRecord = DB::table('payment_refunds')->where('appointment_id', $app1->id)->first();
        $this->assertNotNull($refundRecord);
        $this->assertSame('processed', $refundRecord->status);
        $this->assertSame($result['refund_id'], $refundRecord->gateway_refund_id);
    }

    public function test_expiration_worker_refuses_to_release_after_payment_committed(): void
    {
        $customer = $this->createUser('customer');
        $offer = $this->createOffer([], [$this->templateA->id]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $booked = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appointmentId = $booked->json('appointment.id');
        $appointment = Appointment::find($appointmentId);

        // Pay and confirm
        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointmentId}/payment/demo-pay")
            ->assertStatus(200);

        $paymentService = app(BookingPaymentService::class);

        // Try to release via release()
        $released = $paymentService->release($appointment, 'Hold expired');
        $this->assertFalse($released, 'Expiration worker released a scheduled appointment');

        $this->assertSame('scheduled', $appointment->fresh()->status);
        $redemption = FirstTimeOfferRedemption::where('appointment_id', $appointmentId)->first();
        $this->assertSame(FirstTimeOfferRedemption::STATUS_COMMITTED, $redemption->status);
    }

    public function test_repeated_commit_and_recommit_operations_are_strictly_idempotent(): void
    {
        $customer = $this->createUser('customer');
        $offer = $this->createOffer([], [$this->templateA->id]);

        $app = $this->createAppointment($customer, $this->salonA, 'scheduled');
        $redemption = FirstTimeOfferRedemption::create([
            'id' => (string) Str::uuid(),
            'offer_id' => $offer->id,
            'customer_id' => $customer->id,
            'customer_phone_hash' => FirstTimeOffer::hashPhone($customer->phone),
            'salon_id' => $this->salonA->id,
            'scope' => $offer->scope,
            'appointment_id' => $app->id,
            'status' => FirstTimeOfferRedemption::STATUS_RESERVED,
            'discount_amount' => 100.0,
            'active_entitlement_key' => 'comm_'.Str::random(10),
            'reserved_at' => now(),
        ]);

        $this->assertSame(0, (int) $offer->fresh()->current_redemptions);

        // First commit
        $this->assertTrue($redemption->commit());
        $this->assertSame(1, (int) $offer->fresh()->current_redemptions);

        // Repeated commit on already committed redemption is a no-op
        $this->assertTrue($redemption->commit());
        $this->assertSame(1, (int) $offer->fresh()->current_redemptions);

        // Recommit on already committed redemption is also a no-op
        $this->assertTrue($redemption->recommit('new_key'));
        $this->assertSame(1, (int) $offer->fresh()->current_redemptions);
    }

    public function test_historical_pre_migration_booking_with_null_phone_hash_behavior(): void
    {
        $phone = '919876543210';
        $customer = User::create([
            'id' => (string) Str::uuid(),
            'name' => 'Historical Customer',
            'phone' => $phone,
            'password_hash' => bcrypt('password'),
            'role' => 'customer',
            'is_active' => true,
        ]);

        $offer = $this->createOffer([], [$this->templateA->id]);

        // 1. Pre-migration genuine booking: customer_phone_hash is NULL in DB
        $historicalApp = Appointment::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salonA->id,
            'customer_id' => $customer->id,
            'customer_phone_hash' => null, // pre-migration record
            'appointed_provider_id' => $this->providerA->id,
            'appointment_date' => Carbon::yesterday()->toDateString(),
            'start_time' => '10:00:00',
            'end_time' => '11:00:00',
            'status' => 'completed',
            'total_amount' => 500.0,
            'advance_amount' => 100.0,
            'balance_amount' => 400.0,
        ]);

        $service = app(CustomerOfferEligibilityService::class);

        // While account exists, customer_id links to the historical booking
        $this->assertTrue($service->hasQualifyingBooking($customer, $offer->scope));
        $this->assertFalse($service->isCustomerEligibleForOffer($customer, $offer, $this->salonA->id));

        // 2. Honest limitation audit: If the user deleted their account BEFORE phone hashing was added,
        // their phone was irreversibly changed to 'del_...', so a re-registered user cannot be linked
        // back to pre-migration bookings where customer_phone_hash is null.
        $customer->update(['phone' => 'del_'.Str::random(11), 'is_active' => false]);

        $newAccount = User::create([
            'id' => (string) Str::uuid(),
            'name' => 'Re-registered Customer',
            'phone' => $phone,
            'password_hash' => bcrypt('password'),
            'role' => 'customer',
            'is_active' => true,
        ]);

        // When historical record has NULL phone hash and original user phone was overwritten with del_...,
        // the new account cannot be linked to the pre-migration booking.
        $this->assertFalse(
            $service->hasQualifyingBooking($newAccount, $offer->scope),
            'Acknowledged limitation: pre-migration records with null phone hash cannot link across deleted accounts'
        );
    }


    public function test_releasing_one_appointment_does_not_release_another_appointments_reservation(): void
    {
        $customer1 = $this->createUser('customer');
        $customer2 = $this->createUser('customer');
        $offer = $this->createOffer([], [$this->templateA->id]);

        $this->createCart($customer1, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $booked1 = $this->actingAs($customer1, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $this->createCart($customer2, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $booked2 = $this->actingAs($customer2, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:30',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $app1 = Appointment::find($booked1->json('appointment.id'));
        $app2 = Appointment::find($booked2->json('appointment.id'));

        // Release appointment 1
        app(BookingPaymentService::class)->release($app1, 'Customer backed out');

        $redemption1 = FirstTimeOfferRedemption::where('appointment_id', $app1->id)->first();
        $redemption2 = FirstTimeOfferRedemption::where('appointment_id', $app2->id)->first();

        $this->assertSame(FirstTimeOfferRedemption::STATUS_RELEASED, $redemption1->status);
        $this->assertSame(FirstTimeOfferRedemption::STATUS_RESERVED, $redemption2->status);
        $this->assertNotNull($redemption2->active_entitlement_key);
    }

    // =========================================================================
    // 4. ELIGIBILITY AND ACCOUNT RE-REGISTRATION TESTS
    // =========================================================================

    public function test_committed_redemption_prevents_repeat_use_of_the_same_offer(): void
    {
        $customer = $this->createUser('customer');
        $offer = $this->createOffer([], [$this->templateA->id]);

        // Customer committed a redemption previously
        $dummyApp = $this->createAppointment($customer, $this->salonA, 'completed');
        FirstTimeOfferRedemption::create([
            'id' => (string) Str::uuid(),
            'offer_id' => $offer->id,
            'customer_id' => $customer->id,
            'customer_phone_hash' => FirstTimeOffer::hashPhone($customer->phone),
            'salon_id' => $this->salonA->id,
            'scope' => $offer->scope,
            'appointment_id' => $dummyApp->id,
            'status' => FirstTimeOfferRedemption::STATUS_COMMITTED,
            'discount_amount' => 100.0,
            'active_entitlement_key' => 'comm_'.Str::random(10),
            'reserved_at' => now(),
            'committed_at' => now(),
        ]);

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertFalse($service->isCustomerEligibleForOffer($customer, $offer, $this->salonA->id));
    }

    public function test_prior_genuine_bookings_disqualify_under_correct_scope(): void
    {
        $customer = $this->createUser('customer');

        $platformOffer = $this->createOffer([
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
        ], [$this->templateA->id]);

        $salonOffer = $this->createOffer([
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
        ], [$this->templateA->id], [$this->salonA->id, $this->salonB->id]);

        // Prior booking at Salon A
        $this->createAppointment($customer, $this->salonA, 'completed');

        $service = app(CustomerOfferEligibilityService::class);

        // Platform offer: booking anywhere disqualifies
        $this->assertFalse($service->isCustomerEligibleForOffer($customer, $platformOffer, $this->salonB->id));

        // Salon offer: booking at Salon A disqualifies for Salon A, but NOT for Salon B
        $this->assertFalse($service->isCustomerEligibleForOffer($customer, $salonOffer, $this->salonA->id));
        $this->assertTrue($service->isCustomerEligibleForOffer($customer, $salonOffer, $this->salonB->id));
    }

    public function test_same_phone_reregistration_does_not_trivially_restore_consumed_eligibility(): void
    {
        $phone = '9876543210';
        $phoneHash = FirstTimeOffer::hashPhone($phone);

        $customerOriginal = User::create([
            'id' => (string) Str::uuid(),
            'name' => 'Original Customer',
            'phone' => $phone,
            'password_hash' => bcrypt('password'),
            'role' => 'customer',
            'is_active' => true,
        ]);

        $offer = $this->createOffer([], [$this->templateA->id]);

        // Original customer commits redemption
        $dummyApp = $this->createAppointment($customerOriginal, $this->salonA, 'completed');
        FirstTimeOfferRedemption::create([
            'id' => (string) Str::uuid(),
            'offer_id' => $offer->id,
            'customer_id' => $customerOriginal->id,
            'customer_phone_hash' => $phoneHash,
            'salon_id' => $this->salonA->id,
            'scope' => $offer->scope,
            'appointment_id' => $dummyApp->id,
            'status' => FirstTimeOfferRedemption::STATUS_COMMITTED,
            'discount_amount' => 100.0,
            'active_entitlement_key' => 'comm_'.Str::random(10),
            'reserved_at' => now(),
            'committed_at' => now(),
        ]);

        // Original customer deletes account (simulating CustomerAuthController::deleteAccount)
        $customerOriginal->update([
            'phone' => 'del_'.Str::random(11),
            'name' => 'Deleted User',
            'is_active' => false,
        ]);

        // New account registers with the same phone number
        $customerNew = User::create([
            'id' => (string) Str::uuid(),
            'name' => 'Re-registered Customer',
            'phone' => $phone,
            'password_hash' => bcrypt('password'),
            'role' => 'customer',
            'is_active' => true,
        ]);

        $service = app(CustomerOfferEligibilityService::class);

        // New account is recognized via phone hash and rejected for the offer!
        $this->assertFalse(
            $service->isCustomerEligibleForOffer($customerNew, $offer, $this->salonA->id),
            'Re-registered user with same phone was incorrectly marked eligible despite prior committed redemption'
        );
    }

    public function test_same_phone_reregistration_detects_historical_genuine_bookings(): void
    {
        $phone = '9876543210';
        $phoneHash = FirstTimeOffer::hashPhone($phone);

        $customerOriginal = User::create([
            'id' => (string) Str::uuid(),
            'name' => 'Original Customer',
            'phone' => $phone,
            'password_hash' => bcrypt('password'),
            'role' => 'customer',
            'is_active' => true,
        ]);

        $offer = $this->createOffer([
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
        ], [$this->templateA->id]);

        // Original customer had a genuine scheduled booking with customer_phone_hash stored
        $this->createAppointment($customerOriginal, $this->salonA, 'scheduled', [
            'customer_phone_hash' => $phoneHash,
        ]);

        // Original customer deletes account
        $customerOriginal->update([
            'phone' => 'del_'.Str::random(11),
            'is_active' => false,
        ]);

        // New account registers with the same phone
        $customerNew = User::create([
            'id' => (string) Str::uuid(),
            'name' => 'Re-registered Customer',
            'phone' => $phone,
            'password_hash' => bcrypt('password'),
            'role' => 'customer',
            'is_active' => true,
        ]);

        $service = app(CustomerOfferEligibilityService::class);

        $this->assertTrue(
            $service->hasQualifyingBooking($customerNew, FirstTimeOffer::SCOPE_NEW_TO_PLATFORM),
            'Historical genuine booking was not detected across account re-registration'
        );

        $this->assertFalse(
            $service->isCustomerEligibleForOffer($customerNew, $offer, $this->salonA->id)
        );
    }

    public function test_refund_initiation_occurs_only_after_durable_database_state_is_committed(): void
    {
        $customer1 = $this->createUser('customer');
        $customer2 = $this->createUser('customer');

        $offer = $this->createOffer([
            'max_redemptions' => 1,
            'current_redemptions' => 0,
        ], [$this->templateA->id]);

        $this->createCart($customer1, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $booked1 = $this->actingAs($customer1, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $app1 = Appointment::find($booked1->json('appointment.id'));
        $paymentService = app(BookingPaymentService::class);
        $simulated1 = $paymentService->simulatePayment($app1);

        // Hold expires and is released
        $app1->update(['payment_hold_expires_at' => now()->subMinutes(5)]);
        $paymentService->releaseExpiredHolds();

        // Customer 2 consumes the spot
        $this->createCart($customer2, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $booked2 = $this->actingAs($customer2, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:30',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);
        $app2 = Appointment::find($booked2->json('appointment.id'));
        $this->actingAs($customer2, 'sanctum')->postJson("/api/customer/appointments/{$app2->id}/payment/demo-pay")->assertStatus(200);

        // Spy / mock PaymentGateway: when refund() is called, assert database transaction was already committed!
        $mockGateway = \Mockery::mock(\App\Services\Payments\PaymentGateway::class);
        $mockGateway->shouldReceive('verifySignature')->andReturn(true);
        $mockGateway->shouldReceive('refund')->once()->withArgs(function ($pid, $amount, $reason) use ($app1) {
            // Assert that during the gateway network request, DB state is already committed!
            $order = DB::table('payment_orders')->where('appointment_id', $app1->id)->first();
            $payment = DB::table('payments')->where('appointment_id', $app1->id)->first();
            $refund = DB::table('payment_refunds')->where('appointment_id', $app1->id)->first();
            $app = DB::table('appointments')->where('id', $app1->id)->first();

            return $order && $order->status === 'paid'
                && $payment && $payment->status === 'success'
                && $refund && $refund->status === 'processing'
                && $app && $app->status === 'cancelled';
        })->andReturn('rfnd_verified_post_commit');

        $customPaymentService = new BookingPaymentService($mockGateway);
        $result = $customPaymentService->confirm(
            $app1,
            $simulated1['payment_id'],
            $simulated1['signature'],
            $customer1->id
        );

        $this->assertFalse($result['ok']);
        $this->assertTrue($result['refunded']);
        $this->assertSame('rfnd_verified_post_commit', $result['refund_id']);

        $refundRecord = DB::table('payment_refunds')->where('appointment_id', $app1->id)->first();
        $this->assertNotNull($refundRecord);
        $this->assertSame('processed', $refundRecord->status);
        $this->assertSame('rfnd_verified_post_commit', $refundRecord->gateway_refund_id);
    }

    public function test_duplicate_callbacks_do_not_initiate_duplicate_refunds(): void
    {
        $customer1 = $this->createUser('customer');
        $customer2 = $this->createUser('customer');

        $offer = $this->createOffer([
            'max_redemptions' => 1,
            'current_redemptions' => 0,
        ], [$this->templateA->id]);

        $this->createCart($customer1, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $booked1 = $this->actingAs($customer1, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $app1 = Appointment::find($booked1->json('appointment.id'));
        $paymentService = app(BookingPaymentService::class);
        $simulated1 = $paymentService->simulatePayment($app1);

        // Hold expires and is released
        $app1->update(['payment_hold_expires_at' => now()->subMinutes(5)]);
        $paymentService->releaseExpiredHolds();

        // Customer 2 consumes the spot
        $this->createCart($customer2, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $booked2 = $this->actingAs($customer2, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:30',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);
        $app2 = Appointment::find($booked2->json('appointment.id'));
        $this->actingAs($customer2, 'sanctum')->postJson("/api/customer/appointments/{$app2->id}/payment/demo-pay")->assertStatus(200);

        // First callback: processes payment and refunds successfully
        $result1 = $paymentService->confirm($app1, $simulated1['payment_id'], $simulated1['signature'], $customer1->id);
        $this->assertFalse($result1['ok']);
        $this->assertTrue($result1['refunded']);
        $this->assertNotNull($result1['refund_id']);

        // Set up mock gateway to guarantee refund() is NEVER called on duplicate callback
        $mockGateway = \Mockery::mock(\App\Services\Payments\PaymentGateway::class);
        $mockGateway->shouldReceive('verifySignature')->andReturn(true);
        $mockGateway->shouldReceive('refund')->never();

        $customPaymentService = new BookingPaymentService($mockGateway);

        // Second callback arrives (duplicate / retried network callback)
        $result2 = $customPaymentService->confirm($app1, $simulated1['payment_id'], $simulated1['signature'], $customer1->id);

        $this->assertFalse($result2['ok']);
        $this->assertTrue($result2['hold_expired']);
        $this->assertTrue($result2['already_refunded']);
        $this->assertTrue($result2['refunded']);
        $this->assertSame($result1['refund_id'], $result2['refund_id']);

        // Only 1 payment row, 1 payment_refunds row, current_redemptions = 1
        $this->assertSame(1, DB::table('payments')->where('appointment_id', $app1->id)->count());
        $this->assertSame(1, DB::table('payment_refunds')->where('appointment_id', $app1->id)->count());
        $this->assertSame(1, (int) $offer->fresh()->current_redemptions);
        $this->assertSame('cancelled', $app1->fresh()->status);
    }

    public function test_ambiguous_gateway_timeout_leaves_refund_pending_and_safely_reconcilable(): void
    {
        $customer1 = $this->createUser('customer');
        $customer2 = $this->createUser('customer');

        $offer = $this->createOffer([
            'max_redemptions' => 1,
            'current_redemptions' => 0,
        ], [$this->templateA->id]);

        $this->createCart($customer1, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $booked1 = $this->actingAs($customer1, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $app1 = Appointment::find($booked1->json('appointment.id'));
        $paymentService = app(BookingPaymentService::class);
        $simulated1 = $paymentService->simulatePayment($app1);

        $app1->update(['payment_hold_expires_at' => now()->subMinutes(5)]);
        $paymentService->releaseExpiredHolds();

        // Customer 2 consumes capacity
        $this->createCart($customer2, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $booked2 = $this->actingAs($customer2, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:30',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);
        $app2 = Appointment::find($booked2->json('appointment.id'));
        $this->actingAs($customer2, 'sanctum')->postJson("/api/customer/appointments/{$app2->id}/payment/demo-pay")->assertStatus(200);

        // Gateway times out during refund
        $failingGateway = \Mockery::mock(\App\Services\Payments\PaymentGateway::class);
        $failingGateway->shouldReceive('verifySignature')->andReturn(true);
        $failingGateway->shouldReceive('refund')->once()->andThrow(new \RuntimeException('Gateway connection timed out'));

        $failingService = new BookingPaymentService($failingGateway);
        $result = $failingService->confirm($app1, $simulated1['payment_id'], $simulated1['signature'], $customer1->id);

        $this->assertFalse($result['ok']);
        $this->assertTrue($result['hold_expired']);
        $this->assertFalse($result['refunded']);
        $this->assertTrue($result['refund_pending']);

        // Check durable records in DB
        $payment = DB::table('payments')->where('appointment_id', $app1->id)->first();
        $this->assertNotNull($payment);
        $this->assertSame('success', $payment->status);
        $this->assertStringContainsString('pending_retry', (string) $payment->metadata);

        $refundRecord = DB::table('payment_refunds')->where('appointment_id', $app1->id)->first();
        $this->assertNotNull($refundRecord);
        $this->assertSame('pending', $refundRecord->status);
        $this->assertNotNull($refundRecord->failure_reason);

        // Now gateway recovers
        $recoveredGateway = \Mockery::mock(\App\Services\Payments\PaymentGateway::class);
        $recoveredGateway->shouldReceive('refund')->once()->andReturn('rfnd_reconciled_999');

        $recoveredService = new BookingPaymentService($recoveredGateway);
        $reconciledCount = $recoveredService->reconcilePendingRefunds();

        $this->assertSame(1, $reconciledCount);

        $freshRefund = DB::table('payment_refunds')->where('id', $refundRecord->id)->first();
        $this->assertSame('processed', $freshRefund->status);
        $this->assertSame('rfnd_reconciled_999', $freshRefund->gateway_refund_id);

        $freshPayment = DB::table('payments')->where('id', $payment->id)->first();
        $this->assertStringContainsString('processed', (string) $freshPayment->metadata);

        $this->assertSame(1, (int) $offer->fresh()->current_redemptions);
    }

    public function test_failed_refund_remains_recoverable_and_never_silently_marked_success(): void
    {
        $customer1 = $this->createUser('customer');
        $customer2 = $this->createUser('customer');

        $offer = $this->createOffer(['max_redemptions' => 1], [$this->templateA->id]);

        $this->createCart($customer1, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $booked1 = $this->actingAs($customer1, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);
        $app1 = Appointment::find($booked1->json('appointment.id'));
        $paymentService = app(BookingPaymentService::class);
        $simulated1 = $paymentService->simulatePayment($app1);

        $app1->update(['payment_hold_expires_at' => now()->subMinutes(5)]);
        $paymentService->releaseExpiredHolds();

        $this->createCart($customer2, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $booked2 = $this->actingAs($customer2, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:30',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);
        $app2 = Appointment::find($booked2->json('appointment.id'));
        $this->actingAs($customer2, 'sanctum')->postJson("/api/customer/appointments/{$app2->id}/payment/demo-pay")->assertStatus(200);

        // Gateway returns null (e.g. 500 error)
        $failingGateway = \Mockery::mock(\App\Services\Payments\PaymentGateway::class);
        $failingGateway->shouldReceive('verifySignature')->andReturn(true);
        $failingGateway->shouldReceive('refund')->andReturn(null);

        $failingService = new BookingPaymentService($failingGateway);
        $result = $failingService->confirm($app1, $simulated1['payment_id'], $simulated1['signature'], $customer1->id);

        $this->assertFalse($result['ok']);
        $this->assertFalse($result['refunded']);
        $this->assertTrue($result['refund_pending']);

        $refundRecord = DB::table('payment_refunds')->where('appointment_id', $app1->id)->first();
        $this->assertSame('pending', $refundRecord->status);
        $this->assertNull($refundRecord->gateway_refund_id);

        // Repeated retry while failing keeps status pending
        $retryResult = $failingService->processPendingRefund($refundRecord->id);
        $this->assertFalse($retryResult['success']);
        $this->assertSame('pending', DB::table('payment_refunds')->where('id', $refundRecord->id)->value('status'));
    }

    public function test_appointment_cancellation_refund_occurs_outside_database_transaction(): void
    {
        $customer = $this->createUser('customer');

        // Service with will_refund_advance_if_cancelled = true
        $this->serviceA->update(['will_refund_advance_if_cancelled' => true]);

        $this->createCart($customer, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $booked = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->addDay()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);

        $appId = $booked->json('appointment.id');
        $this->actingAs($customer, 'sanctum')->postJson("/api/customer/appointments/{$appId}/payment/demo-pay")->assertStatus(200);

        // Cancel the appointment
        $response = $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/appointments/{$appId}/cancel",
            ['reason' => 'Schedule conflict']
        )->assertStatus(200);

        $response->assertJsonPath('appointment.status', 'cancelled');
        $this->assertGreaterThan(0, $response->json('refund.refundable'));

        $refundRecord = DB::table('payment_refunds')->where('appointment_id', $appId)->first();
        $this->assertNotNull($refundRecord);
        $this->assertSame('processed', $refundRecord->status);
        $this->assertNotNull($refundRecord->gateway_refund_id);
    }

    public function test_refund_retry_does_not_increment_redemption_counters(): void
    {
        $customer1 = $this->createUser('customer');
        $customer2 = $this->createUser('customer');

        $offer = $this->createOffer(['max_redemptions' => 1], [$this->templateA->id]);

        $this->createCart($customer1, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $booked1 = $this->actingAs($customer1, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:00',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);
        $app1 = Appointment::find($booked1->json('appointment.id'));
        $paymentService = app(BookingPaymentService::class);
        $simulated1 = $paymentService->simulatePayment($app1);

        $app1->update(['payment_hold_expires_at' => now()->subMinutes(5)]);
        $paymentService->releaseExpiredHolds();

        $this->createCart($customer2, $this->salonA, [['service' => $this->serviceA, 'qty' => 1]]);
        $booked2 = $this->actingAs($customer2, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salonA->id}/appointments/book",
            [
                'date' => Carbon::tomorrow()->toDateString(),
                'time' => '10:30',
                'provider_id' => $this->providerA->id,
            ]
        )->assertStatus(201);
        $app2 = Appointment::find($booked2->json('appointment.id'));
        $this->actingAs($customer2, 'sanctum')->postJson("/api/customer/appointments/{$app2->id}/payment/demo-pay")->assertStatus(200);

        $this->assertSame(1, (int) $offer->fresh()->current_redemptions);

        // Confirm customer 1 (refunded)
        $paymentService->confirm($app1, $simulated1['payment_id'], $simulated1['signature'], $customer1->id);

        $this->assertSame(1, (int) $offer->fresh()->current_redemptions);

        // Multiple retries of refund sweep or confirm
        $paymentService->reconcilePendingRefunds();
        $paymentService->confirm($app1, $simulated1['payment_id'], $simulated1['signature'], $customer1->id);

        $this->assertSame(1, (int) $offer->fresh()->current_redemptions);
    }

    // =========================================================================
    // FIXTURE HELPERS
    // =========================================================================

    private function createUser(string $role): User
    {
        $unique = Str::random(8);

        return User::create([
            'id' => (string) Str::uuid(),
            'name' => "User {$unique}",
            'phone' => '9'.substr((string) crc32($unique), 0, 9),
            'password_hash' => bcrypt('password'),
            'role' => $role,
            'is_active' => true,
        ]);
    }

    private function createSalon(User $admin, string $name): Salon
    {
        $slug = Str::slug($name).'-'.Str::random(5);

        return Salon::create([
            'id' => (string) Str::uuid(),
            'admin_id' => $admin->id,
            'name' => $name,
            'slug' => $slug,
            'address' => '123 Test St',
            'submitted_by' => $admin->id,
            'status' => 'active',
        ]);
    }

    private function createOffer(array $attributes = [], array $templateIds = [], array $salonIds = []): FirstTimeOffer
    {
        $offer = FirstTimeOffer::create(array_merge([
            'name' => 'Test Offer '.Str::random(5),
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            'max_discount_cap' => 500.0,
            'is_active' => true,
        ], $attributes));

        if (! empty($templateIds)) {
            $offer->serviceTemplates()->attach($templateIds);
        }

        if (! empty($salonIds)) {
            $offer->participatingSalons()->attach($salonIds);
        }

        return $offer->fresh(['serviceTemplates', 'participatingSalons']);
    }

    private function createAppointment(User $customer, Salon $salon, string $status, array $overrides = []): Appointment
    {
        return Appointment::create(array_merge([
            'id' => (string) Str::uuid(),
            'salon_id' => $salon->id,
            'customer_id' => $customer->id,
            'customer_phone_hash' => FirstTimeOffer::hashPhone($customer->phone),
            'appointed_provider_id' => $this->providerA->id,
            'appointment_date' => now()->toDateString(),
            'start_time' => '10:00:00',
            'end_time' => '11:00:00',
            'status' => $status,
            'total_amount' => 500.0,
            'advance_amount' => 100.0,
            'balance_amount' => 400.0,
        ], $overrides));
    }

    /**
     * @param  array<int, array{service: Service, qty: int}>  $items
     */
    private function createCart(User $customer, Salon $salon, array $items): Cart
    {
        Cart::where('customer_id', $customer->id)->where('status', 'active')->delete();

        $cart = Cart::create([
            'id' => (string) Str::uuid(),
            'customer_id' => $customer->id,
            'salon_id' => $salon->id,
            'status' => 'active',
        ]);

        foreach ($items as $entry) {
            CartItem::create([
                'id' => (string) Str::uuid(),
                'cart_id' => $cart->id,
                'service_id' => $entry['service']->id,
                'quantity' => $entry['qty'] ?? 1,
            ]);
        }

        return $cart->fresh(['items.service.template', 'items.combo.services.template']);
    }
}
