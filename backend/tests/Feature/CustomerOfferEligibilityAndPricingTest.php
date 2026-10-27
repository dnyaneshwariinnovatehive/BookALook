<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\Combo;
use App\Models\FirstTimeOffer;
use App\Models\FirstTimeOfferRedemption;
use App\Models\Salon;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceProvider;
use App\Models\ServiceTemplate;
use App\Models\User;
use App\Services\CartPricingService;
use App\Services\CustomerOfferEligibilityService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class CustomerOfferEligibilityAndPricingTest extends TestCase
{
    use DatabaseTransactions;

    private User $customer;
    private User $admin;
    private Salon $salonA;
    private Salon $salonB;
    private ServiceCategory $category;
    private ServiceTemplate $templateA;
    private ServiceTemplate $templateB;
    private ServiceTemplate $templateC;
    private Service $serviceA;
    private Service $serviceB;
    private Service $serviceC;
    private ServiceProvider $providerA;

    protected function setUp(): void
    {
        parent::setUp();

        $this->admin = $this->createUser('superadmin');
        $this->customer = $this->createUser('customer');

        $this->salonA = $this->createSalon($this->admin, 'Salon Alpha');
        $this->salonB = $this->createSalon($this->admin, 'Salon Beta');

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
            'estimated_duration_minutes' => 20,
            'is_active' => true,
        ]);

        $this->templateC = ServiceTemplate::create([
            'id' => (string) Str::uuid(),
            'name' => 'Facial ' . Str::random(5),
            'category_id' => $this->category->id,
            'estimated_duration_minutes' => 45,
            'is_active' => true,
        ]);

        $this->serviceA = Service::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salonA->id,
            'template_id' => $this->templateA->id,
            'price' => 500.0,
            'advance_percentage' => 20.0,
            'is_active' => true,
        ]);

        $this->serviceB = Service::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salonA->id,
            'template_id' => $this->templateB->id,
            'price' => 300.0,
            'advance_percentage' => 20.0,
            'is_active' => true,
        ]);

        $this->serviceC = Service::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salonA->id,
            'template_id' => $this->templateC->id,
            'price' => 1000.0,
            'advance_percentage' => 20.0,
            'is_active' => true,
        ]);

        $this->providerA = ServiceProvider::create([
            'id' => (string) Str::uuid(),
            'user_id' => $this->createUser('provider')->id,
            'salon_id' => $this->salonA->id,
            'is_active' => true,
        ]);
    }

    // =========================================================================
    // SECTION 1: ELIGIBILITY TESTS
    // =========================================================================

    public function test_new_customer_with_no_previous_bookings_is_eligible(): void
    {
        $offer = $this->createOffer([
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
        ], [$this->templateA->id]);

        $service = app(CustomerOfferEligibilityService::class);

        $this->assertFalse($service->hasQualifyingBooking($this->customer->id, FirstTimeOffer::SCOPE_NEW_TO_PLATFORM));
        $this->assertTrue($service->isCustomerEligibleForOffer($this->customer, $offer, $this->salonA->id));
    }

    public function test_previous_scheduled_booking_disqualifies_customer(): void
    {
        $this->createAppointment($this->customer, $this->salonA, 'scheduled');

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertTrue($service->hasQualifyingBooking($this->customer->id, FirstTimeOffer::SCOPE_NEW_TO_PLATFORM));
    }

    public function test_previous_in_progress_booking_disqualifies_customer(): void
    {
        $this->createAppointment($this->customer, $this->salonA, 'in_progress');

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertTrue($service->hasQualifyingBooking($this->customer->id, FirstTimeOffer::SCOPE_NEW_TO_PLATFORM));
    }

    public function test_previous_completed_booking_disqualifies_customer(): void
    {
        $this->createAppointment($this->customer, $this->salonA, 'completed');

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertTrue($service->hasQualifyingBooking($this->customer->id, FirstTimeOffer::SCOPE_NEW_TO_PLATFORM));
    }

    public function test_previous_no_show_disqualifies_customer(): void
    {
        $this->createAppointment($this->customer, $this->salonA, 'no_show');

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertTrue($service->hasQualifyingBooking($this->customer->id, FirstTimeOffer::SCOPE_NEW_TO_PLATFORM));
    }

    public function test_previous_genuine_customer_cancellation_disqualifies_customer(): void
    {
        $this->createAppointment($this->customer, $this->salonA, 'cancelled', [
            'cancelled_by' => 'customer',
            'cancellation_reason' => 'Change of plans',
        ]);

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertTrue($service->hasQualifyingBooking($this->customer->id, FirstTimeOffer::SCOPE_NEW_TO_PLATFORM));
    }

    public function test_previous_genuine_partner_cancellation_disqualifies_customer(): void
    {
        $this->createAppointment($this->customer, $this->salonA, 'cancelled', [
            'cancelled_by' => 'salon',
            'cancellation_reason' => 'Emergency power outage',
        ]);

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertTrue($service->hasQualifyingBooking($this->customer->id, FirstTimeOffer::SCOPE_NEW_TO_PLATFORM));
    }

    public function test_booking_at_another_salon_disqualifies_under_platform_wide_scope(): void
    {
        $this->createAppointment($this->customer, $this->salonB, 'completed');

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertTrue($service->hasQualifyingBooking($this->customer->id, FirstTimeOffer::SCOPE_NEW_TO_PLATFORM, $this->salonA->id));
    }

    public function test_booking_at_another_salon_does_not_disqualify_under_salon_specific_scope(): void
    {
        // Booking is at salonB
        $this->createAppointment($this->customer, $this->salonB, 'completed');

        $service = app(CustomerOfferEligibilityService::class);
        // Under new_to_salon for salonA, customer has NO booking at salonA
        $this->assertFalse($service->hasQualifyingBooking($this->customer->id, FirstTimeOffer::SCOPE_NEW_TO_SALON, $this->salonA->id));
        // Under new_to_salon for salonB, customer DOES have a booking
        $this->assertTrue($service->hasQualifyingBooking($this->customer->id, FirstTimeOffer::SCOPE_NEW_TO_SALON, $this->salonB->id));
    }

    public function test_pending_payment_hold_does_not_disqualify_customer(): void
    {
        $this->createAppointment($this->customer, $this->salonA, 'pending_payment');

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertFalse($service->hasQualifyingBooking($this->customer->id, FirstTimeOffer::SCOPE_NEW_TO_PLATFORM));
    }

    public function test_system_cancelled_abandoned_hold_does_not_disqualify_customer(): void
    {
        $this->createAppointment($this->customer, $this->salonA, 'cancelled', [
            'cancelled_by' => 'system',
            'cancellation_reason' => 'Payment was not completed in time.',
        ]);

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertFalse($service->hasQualifyingBooking($this->customer->id, FirstTimeOffer::SCOPE_NEW_TO_PLATFORM));
    }

    public function test_failed_payment_attempt_does_not_disqualify_customer(): void
    {
        $apt = $this->createAppointment($this->customer, $this->salonA, 'cancelled', [
            'cancelled_by' => 'system',
            'cancellation_reason' => 'Replaced by newer attempt.',
        ]);

        DB::table('payments')->insert([
            'id' => (string) Str::uuid(),
            'appointment_id' => $apt->id,
            'payment_type' => 'advance',
            'amount' => 100.0,
            'currency' => 'INR',
            'status' => 'failed',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertFalse($service->hasQualifyingBooking($this->customer->id, FirstTimeOffer::SCOPE_NEW_TO_PLATFORM));
    }

    public function test_inactive_offer_is_not_eligible(): void
    {
        $offer = $this->createOffer([
            'is_active' => false,
        ], [$this->templateA->id]);

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertFalse($service->isCustomerEligibleForOffer($this->customer, $offer, $this->salonA->id));
    }

    public function test_offer_before_start_date_is_not_eligible(): void
    {
        $offer = $this->createOffer([
            'starts_at' => Carbon::now()->addDays(2),
        ], [$this->templateA->id]);

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertFalse($service->isCustomerEligibleForOffer($this->customer, $offer, $this->salonA->id));
    }

    public function test_offer_after_end_date_is_not_eligible(): void
    {
        $offer = $this->createOffer([
            'starts_at' => Carbon::now()->subDays(5),
            'ends_at' => Carbon::now()->subDay(),
        ], [$this->templateA->id]);

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertFalse($service->isCustomerEligibleForOffer($this->customer, $offer, $this->salonA->id));
    }

    public function test_non_participating_salon_is_not_eligible(): void
    {
        // Salon-specific offer explicitly for salonB only
        $offer = $this->createOffer([
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
        ], [$this->templateA->id], [$this->salonB->id]);

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertFalse($service->isCustomerEligibleForOffer($this->customer, $offer, $this->salonA->id));
        $this->assertTrue($service->isCustomerEligibleForOffer($this->customer, $offer, $this->salonB->id));
    }

    public function test_unselected_service_template_is_not_eligible(): void
    {
        // Offer only targets templateA
        $offer = $this->createOffer([], [$this->templateA->id]);

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertTrue($service->isServiceEligibleForOffer($this->serviceA, $offer));
        $this->assertFalse($service->isServiceEligibleForOffer($this->serviceB, $offer));
    }

    public function test_inactive_service_instance_is_not_eligible(): void
    {
        $inactiveTemplate = ServiceTemplate::create([
            'id' => (string) Str::uuid(),
            'name' => 'Inactive Temp ' . Str::random(5),
            'category_id' => $this->category->id,
            'estimated_duration_minutes' => 30,
            'is_active' => true,
        ]);
        $offer = $this->createOffer([], [$inactiveTemplate->id]);
        $inactiveService = Service::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salonA->id,
            'template_id' => $inactiveTemplate->id,
            'price' => 500.0,
            'is_active' => false,
        ]);

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertFalse($service->isServiceEligibleForOffer($inactiveService, $offer));
    }

    public function test_previously_committed_redemption_disqualifies_customer(): void
    {
        $offer = $this->createOffer([], [$this->templateA->id]);

        FirstTimeOfferRedemption::create([
            'id' => (string) Str::uuid(),
            'offer_id' => $offer->id,
            'customer_id' => $this->customer->id,
            'salon_id' => $this->salonA->id,
            'status' => 'committed',
            'scope' => $offer->scope,
            'discount_amount' => 100.0,
            'reserved_at' => now()->subDay(),
            'committed_at' => now(),
        ]);

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertFalse($service->isCustomerEligibleForOffer($this->customer, $offer, $this->salonA->id));
    }

    // =========================================================================
    // SECTION 2: PRICING TESTS
    // =========================================================================

    public function test_percentage_discount_without_cap_reached(): void
    {
        // 20% discount on Service A (500) and Service B (300). List total = 800. Expected discount = 160.
        $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            'max_discount_cap' => 500.0,
        ], [$this->templateA->id, $this->templateB->id]);

        $cart = $this->createCart($this->customer, $this->salonA, [
            ['service' => $this->serviceA, 'qty' => 1],
            ['service' => $this->serviceB, 'qty' => 1],
        ]);

        $priced = app(CartPricingService::class)->price($cart);

        $this->assertEquals(800.0, $priced['list_total']);
        $this->assertEquals(640.0, $priced['total']);
        $this->assertEquals(160.0, $priced['saving']);
        $this->assertTrue($priced['first_time_discount']['applied']);
        $this->assertEquals(160.0, $priced['first_time_discount']['total_discount']);

        // Check line allocations
        $lines = $priced['first_time_discount']['lines'];
        $this->assertEquals(100.0, $lines[$this->serviceA->id]['line_discount']);
        $this->assertEquals(60.0, $lines[$this->serviceB->id]['line_discount']);
    }

    public function test_percentage_discount_with_booking_cap_reached(): void
    {
        // 20% on Service A (500) and Service C (1000). Total = 1500.
        // Unconstrained potential discount: 100 + 200 = 300.
        // Cap is set to 150.
        $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            'max_discount_cap' => 150.0,
        ], [$this->templateA->id, $this->templateC->id]);

        $cart = $this->createCart($this->customer, $this->salonA, [
            ['service' => $this->serviceA, 'qty' => 1],
            ['service' => $this->serviceC, 'qty' => 1],
        ]);

        $priced = app(CartPricingService::class)->price($cart);

        $this->assertEquals(1500.0, $priced['list_total']);
        $this->assertEquals(1350.0, $priced['total']);
        $this->assertEquals(150.0, $priced['saving']);
        $this->assertEquals(150.0, $priced['first_time_discount']['total_discount']);

        // Sum of line allocations must equal exactly 150.0
        $lines = $priced['first_time_discount']['lines'];
        $sumLines = $lines[$this->serviceA->id]['line_discount'] + $lines[$this->serviceC->id]['line_discount'];
        $this->assertEquals(150.0, $sumLines);
        // Proportional: Service A potential 100/300 (1/3) = 50. Service C potential 200/300 (2/3) = 100.
        $this->assertEquals(50.0, $lines[$this->serviceA->id]['line_discount']);
        $this->assertEquals(100.0, $lines[$this->serviceC->id]['line_discount']);
    }

    public function test_flat_discount_for_one_eligible_service(): void
    {
        // Flat 100 on Service A (500)
        $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_FLAT,
            'discount_value' => 100.0,
            'flat_booking_cap' => 1000.0,
        ], [$this->templateA->id]);

        $cart = $this->createCart($this->customer, $this->salonA, [
            ['service' => $this->serviceA, 'qty' => 1],
        ]);

        $priced = app(CartPricingService::class)->price($cart);

        $this->assertEquals(500.0, $priced['list_total']);
        $this->assertEquals(400.0, $priced['total']);
        $this->assertEquals(100.0, $priced['first_time_discount']['total_discount']);
    }

    public function test_flat_discount_for_multiple_eligible_services(): void
    {
        // Flat 150 per service on Service A (500) and Service B (300). Total discount = 300.
        $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_FLAT,
            'discount_value' => 150.0,
            'flat_booking_cap' => 1000.0,
        ], [$this->templateA->id, $this->templateB->id]);

        $cart = $this->createCart($this->customer, $this->salonA, [
            ['service' => $this->serviceA, 'qty' => 1],
            ['service' => $this->serviceB, 'qty' => 1],
        ]);

        $priced = app(CartPricingService::class)->price($cart);

        $this->assertEquals(800.0, $priced['list_total']);
        $this->assertEquals(500.0, $priced['total']);
        $this->assertEquals(300.0, $priced['first_time_discount']['total_discount']);
        $this->assertEquals(150.0, $priced['first_time_discount']['lines'][$this->serviceA->id]['line_discount']);
        $this->assertEquals(150.0, $priced['first_time_discount']['lines'][$this->serviceB->id]['line_discount']);
    }

    public function test_flat_discount_with_booking_cap_reached(): void
    {
        // Flat 200 per service on 3 services. Unconstrained = 600. Cap = 450.
        $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_FLAT,
            'discount_value' => 200.0,
            'max_discount_cap' => 450.0,
        ], [$this->templateA->id, $this->templateB->id, $this->templateC->id]);

        $cart = $this->createCart($this->customer, $this->salonA, [
            ['service' => $this->serviceA, 'qty' => 1],
            ['service' => $this->serviceB, 'qty' => 1],
            ['service' => $this->serviceC, 'qty' => 1],
        ]);

        $priced = app(CartPricingService::class)->price($cart);

        $this->assertEquals(1800.0, $priced['list_total']);
        $this->assertEquals(1350.0, $priced['total']);
        $this->assertEquals(450.0, $priced['first_time_discount']['total_discount']);

        // Check line sum
        $lines = $priced['first_time_discount']['lines'];
        $sum = $lines[$this->serviceA->id]['line_discount'] +
               $lines[$this->serviceB->id]['line_discount'] +
               $lines[$this->serviceC->id]['line_discount'];
        $this->assertEquals(450.0, $sum);
    }

    public function test_service_price_below_configured_flat_amount(): void
    {
        // Flat 600 on Service A (500). Discount cannot exceed 500.
        $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_FLAT,
            'discount_value' => 600.0,
            'flat_booking_cap' => 1000.0,
        ], [$this->templateA->id]);

        $cart = $this->createCart($this->customer, $this->salonA, [
            ['service' => $this->serviceA, 'qty' => 1],
        ]);

        $priced = app(CartPricingService::class)->price($cart);

        $this->assertEquals(500.0, $priced['first_time_discount']['total_discount']);
        $this->assertEquals(0.0, $priced['total']);
    }

    public function test_each_minimum_condition_passing_and_failing(): void
    {
        // 1. Min Service Price test
        $offerMinPrice = $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            'min_service_price' => 400.0, // Service A (500) qualifies; Service B (300) fails
        ], [$this->templateA->id, $this->templateB->id]);

        $cart = $this->createCart($this->customer, $this->salonA, [
            ['service' => $this->serviceA, 'qty' => 1],
            ['service' => $this->serviceB, 'qty' => 1],
        ]);

        $priced = app(CartPricingService::class)->price($cart);
        // Only Service A gets 20% of 500 = 100
        $this->assertEquals(100.0, $priced['first_time_discount']['total_discount']);
        $this->assertEquals(100.0, $priced['first_time_discount']['lines'][$this->serviceA->id]['line_discount']);
        $this->assertEquals(0.0, $priced['first_time_discount']['lines'][$this->serviceB->id]['line_discount']);

        // 2. Min Eligible Subtotal: requires 600 eligible subtotal.
        // Cart has only Service A (500) -> fails condition
        $offerMinPrice->delete();
        $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            'min_eligible_subtotal' => 600.0,
        ], [$this->templateA->id]);

        $cartSingle = $this->createCart($this->customer, $this->salonA, [
            ['service' => $this->serviceA, 'qty' => 1], // only 500
        ]);

        $pricedSingle = app(CartPricingService::class)->price($cartSingle);
        $this->assertFalse($pricedSingle['first_time_discount']['applied']);
        $this->assertEquals(0.0, $pricedSingle['first_time_discount']['total_discount']);

        // 3. Min Total Booking Subtotal: requires 1200 total booking subtotal.
        // Cart total is 800 -> fails; add Service C (1000) -> total 1800 -> passes!
        $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 10.0,
            'min_total_booking_subtotal' => 1200.0,
        ], [$this->templateA->id, $this->templateB->id, $this->templateC->id]);

        // Below 1200:
        $cartUnder = $this->createCart($this->customer, $this->salonA, [
            ['service' => $this->serviceA, 'qty' => 1],
            ['service' => $this->serviceB, 'qty' => 1],
        ]);
        $pricedUnder = app(CartPricingService::class)->price($cartUnder);
        $this->assertFalse($pricedUnder['first_time_discount']['applied']);

        // Meets 1200:
        $cartOver = $this->createCart($this->customer, $this->salonA, [
            ['service' => $this->serviceA, 'qty' => 1],
            ['service' => $this->serviceC, 'qty' => 1],
        ]);
        $pricedOver = app(CartPricingService::class)->price($cartOver);
        $this->assertTrue($pricedOver['first_time_discount']['applied']);
        $this->assertEquals(150.0, $pricedOver['first_time_discount']['total_discount']);
    }

    public function test_unselected_service_stays_at_regular_price(): void
    {
        // Offer targets ONLY templateA
        $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
        ], [$this->templateA->id]);

        $cart = $this->createCart($this->customer, $this->salonA, [
            ['service' => $this->serviceA, 'qty' => 1],
            ['service' => $this->serviceB, 'qty' => 1],
        ]);

        $priced = app(CartPricingService::class)->price($cart);

        // Service A (500) gets 100 off; Service B (300) gets 0 off
        $this->assertEquals(100.0, $priced['first_time_discount']['total_discount']);
        $this->assertEquals(100.0, $priced['first_time_discount']['lines'][$this->serviceA->id]['line_discount']);
        $this->assertEquals(0.0, $priced['first_time_discount']['lines'][$this->serviceB->id]['line_discount']);
        $this->assertEquals(300.0, $priced['first_time_discount']['lines'][$this->serviceB->id]['final_line_price']);
    }

    public function test_newly_created_service_template_is_not_auto_enrolled(): void
    {
        // Existing offer targets templateA
        $offer = $this->createOffer([], [$this->templateA->id]);

        // A new template is added to the system
        $newTemplate = ServiceTemplate::create([
            'id' => (string) Str::uuid(),
            'name' => 'Brand New Treatment',
            'category_id' => $this->category->id,
            'estimated_duration_minutes' => 60,
            'is_active' => true,
        ]);

        $newService = Service::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salonA->id,
            'template_id' => $newTemplate->id,
            'price' => 700.0,
            'is_active' => true,
        ]);

        $service = app(CustomerOfferEligibilityService::class);
        $this->assertFalse($service->isServiceEligibleForOffer($newService, $offer));
    }

    public function test_platform_wide_versus_salon_specific_scope(): void
    {
        // Offer 1: new_to_platform
        $offerPlatform = $this->createOffer([
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
        ], [$this->templateA->id]);

        // Customer has a past booking at Salon B
        $this->createAppointment($this->customer, $this->salonB, 'completed');

        $eligibility = app(CustomerOfferEligibilityService::class);

        // Platform offer is NOT eligible because customer booked anywhere
        $this->assertFalse($eligibility->isCustomerEligibleForOffer($this->customer, $offerPlatform, $this->salonA->id));

        // Offer 2: new_to_salon for Salon A
        $offerSalon = $this->createOffer([
            'scope' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
        ], [$this->templateA->id], [$this->salonA->id]);

        // Salon offer IS eligible because customer has zero bookings at Salon A
        $this->assertTrue($eligibility->isCustomerEligibleForOffer($this->customer, $offerSalon, $this->salonA->id));
    }

    public function test_multiple_offers_do_not_stack_and_deterministic_selection(): void
    {
        // Offer 1: 10% off (on 500 = 50 off)
        $this->createOffer([
            'name' => 'Offer 10 Percent',
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 10.0,
        ], [$this->templateA->id]);

        // Offer 2: 25% off (on 500 = 125 off)
        $offerBetter = $this->createOffer([
            'name' => 'Offer 25 Percent',
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 25.0,
        ], [$this->templateA->id]);

        // Offer 3: Flat 50 off
        $this->createOffer([
            'name' => 'Offer Flat 50',
            'discount_type' => FirstTimeOffer::TYPE_FLAT,
            'discount_value' => 50.0,
        ], [$this->templateA->id]);

        $cart = $this->createCart($this->customer, $this->salonA, [
            ['service' => $this->serviceA, 'qty' => 1],
        ]);

        $priced = app(CartPricingService::class)->price($cart);

        // They do NOT stack: only the single greatest offer is applied
        $this->assertEquals(125.0, $priced['first_time_discount']['total_discount']);
        $this->assertSame($offerBetter->id, $priced['first_time_discount']['offer_id']);
        $this->assertSame('Offer 25 Percent', $priced['first_time_discount']['offer_name']);
    }

    public function test_combo_only_cart_is_unchanged(): void
    {
        // Offer active on all templates
        $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
        ], [$this->templateA->id, $this->templateB->id]);

        $combo = Combo::create([
            'salon_id' => $this->salonA->id,
            'name' => 'Haircut and Shave Combo',
            'advance_percentage' => 20.0,
            'is_active' => true,
        ]);
        $combo->services()->attach($this->serviceA->id, ['combo_special_price' => 400.0]);
        $combo->services()->attach($this->serviceB->id, ['combo_special_price' => 200.0]);

        // Cart with loose services that perfectly match the combo
        $cart = $this->createCart($this->customer, $this->salonA, [
            ['service' => $this->serviceA, 'qty' => 1],
            ['service' => $this->serviceB, 'qty' => 1],
        ]);

        $priced = app(CartPricingService::class)->price($cart);

        // Absorbed by combo (400 + 200 = 600)
        $this->assertEquals(600.0, $priced['total']);
        $this->assertEquals(800.0, $priced['list_total']);
        $this->assertCount(1, $priced['applied_combos']);
        // No loose services left -> first time discount is 0
        $this->assertSame([], $priced['loose_services']);
        $this->assertFalse($priced['first_time_discount']['applied']);
        $this->assertEquals(0.0, $priced['first_time_discount']['total_discount']);
    }

    public function test_combo_plus_eligible_loose_service_discounts_only_loose_service(): void
    {
        $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
        ], [$this->templateA->id, $this->templateB->id, $this->templateC->id]);

        $combo = Combo::create([
            'salon_id' => $this->salonA->id,
            'name' => 'Haircut and Shave Combo',
            'advance_percentage' => 20.0,
            'is_active' => true,
        ]);
        $combo->services()->attach($this->serviceA->id, ['combo_special_price' => 400.0]);
        $combo->services()->attach($this->serviceB->id, ['combo_special_price' => 200.0]);

        // Cart holds Service A, Service B, AND Service C (1000 list)
        $cart = $this->createCart($this->customer, $this->salonA, [
            ['service' => $this->serviceA, 'qty' => 1],
            ['service' => $this->serviceB, 'qty' => 1],
            ['service' => $this->serviceC, 'qty' => 1],
        ]);

        $priced = app(CartPricingService::class)->price($cart);

        // Combo absorbs A + B for 600 (saving 200)
        $this->assertCount(1, $priced['applied_combos']);

        // Service C is loose (1000 list). First time discount 20% on 1000 = 200.
        $this->assertTrue($priced['first_time_discount']['applied']);
        $this->assertEquals(200.0, $priced['first_time_discount']['total_discount']);

        // Total = 600 (combo) + 800 (discounted Service C) = 1400.
        // List total = 500 + 300 + 1000 = 1800.
        $this->assertEquals(1800.0, $priced['list_total']);
        $this->assertEquals(1400.0, $priced['total']);
        $this->assertEquals(400.0, $priced['saving']); // 200 from combo + 200 from first-time offer
    }

    public function test_all_monetary_totals_and_allocated_line_discounts_reconcile_exactly(): void
    {
        // 15% discount on 3 services: 333, 444, 555
        // Total = 1332. 15% potential = 199.80.
        // Cap set to 123.45.
        $this->serviceA->update(['price' => 333.0]);
        $this->serviceB->update(['price' => 444.0]);
        $this->serviceC->update(['price' => 555.0]);

        $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 15.0,
            'max_discount_cap' => 123.45,
        ], [$this->templateA->id, $this->templateB->id, $this->templateC->id]);

        $cart = $this->createCart($this->customer, $this->salonA, [
            ['service' => $this->serviceA->fresh(), 'qty' => 1],
            ['service' => $this->serviceB->fresh(), 'qty' => 1],
            ['service' => $this->serviceC->fresh(), 'qty' => 1],
        ]);

        $priced = app(CartPricingService::class)->price($cart);

        $this->assertEquals(123.45, $priced['first_time_discount']['total_discount']);

        $lines = $priced['first_time_discount']['lines'];
        $sumLines = array_sum(array_column($lines, 'line_discount'));
        $this->assertEquals(123.45, round($sumLines, 2));

        $this->assertEquals(round(1332.0 - 123.45, 2), $priced['total']);
    }

    // =========================================================================
    // SECTION 3: API TESTS
    // =========================================================================

    public function test_authenticated_eligible_customer_receives_correct_personalized_metadata(): void
    {
        $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
            'max_discount_cap' => 500.0,
        ], [$this->templateA->id]);

        $res = $this->actingAs($this->customer, 'sanctum')
            ->getJson("/api/customer/salons/{$this->salonA->id}");

        $res->assertOk();
        $json = $res->json('salon');

        $this->assertNotNull($json['first_time_offer']);
        $this->assertTrue($json['first_time_offer']['eligible']);
        $this->assertEquals(20.0, $json['first_time_offer']['discount_value']);

        // Check services array
        $services = collect($json['services']);
        $srvA = $services->firstWhere('id', $this->serviceA->id);
        $this->assertNotNull($srvA);
        $this->assertEquals(500.0, $srvA['original_price']);
        $this->assertEquals(400.0, $srvA['discounted_price']);
        $this->assertNotNull($srvA['first_time_discount']);
        $this->assertEquals(100.0, $srvA['first_time_discount']['discount_amount']);
        $this->assertSame('20% OFF', $srvA['first_time_discount']['discount_label']);

        // Service B was not targeted
        $srvB = $services->firstWhere('id', $this->serviceB->id);
        $this->assertEquals(300.0, $srvB['original_price']);
        $this->assertEquals(300.0, $srvB['discounted_price']);
        $this->assertNull($srvB['first_time_discount']);
    }

    public function test_ineligible_customer_receives_regular_pricing(): void
    {
        $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
        ], [$this->templateA->id]);

        // Customer has a past completed booking
        $this->createAppointment($this->customer, $this->salonA, 'completed');

        $res = $this->actingAs($this->customer, 'sanctum')
            ->getJson("/api/customer/salons/{$this->salonA->id}");

        $res->assertOk();
        $json = $res->json('salon');

        $this->assertNull($json['first_time_offer']);

        $services = collect($json['services']);
        $srvA = $services->firstWhere('id', $this->serviceA->id);
        $this->assertEquals(500.0, $srvA['original_price']);
        $this->assertEquals(500.0, $srvA['discounted_price']);
        $this->assertNull($srvA['first_time_discount']);
    }

    public function test_guest_receives_regular_pricing(): void
    {
        $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
        ], [$this->templateA->id]);

        $res = $this->getJson("/api/customer/salons/{$this->salonA->id}");

        $res->assertOk();
        $json = $res->json('salon');

        $this->assertNull($json['first_time_offer']);

        $services = collect($json['services']);
        $srvA = $services->firstWhere('id', $this->serviceA->id);
        $this->assertEquals(500.0, $srvA['original_price']);
        $this->assertEquals(500.0, $srvA['discounted_price']);
        $this->assertNull($srvA['first_time_discount']);
    }

    public function test_catalog_pricing_does_not_create_redemptions_or_increment_counters(): void
    {
        $offer = $this->createOffer([
            'discount_type' => FirstTimeOffer::TYPE_PERCENTAGE,
            'discount_value' => 20.0,
        ], [$this->templateA->id]);

        $this->assertSame(0, $offer->current_redemptions);
        $this->assertSame(0, FirstTimeOfferRedemption::count());

        $this->actingAs($this->customer)->getJson("/api/customer/salons/{$this->salonA->id}");

        $offer->refresh();
        $this->assertSame(0, $offer->current_redemptions);
        $this->assertSame(0, FirstTimeOfferRedemption::count());
    }

    // =========================================================================
    // HELPER METHODS
    // =========================================================================

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
            'address' => '123 Test St',
            'submitted_by' => $admin->id,
            'status' => 'active',
        ]);
    }

    private function createOffer(array $attributes = [], array $templateIds = [], array $salonIds = []): FirstTimeOffer
    {
        $offer = FirstTimeOffer::create(array_merge([
            // Offers belong to a salon now; the first participating salon, else the main one.
            'salon_id' => $salonIds[0] ?? $this->salonA->id,
            'name' => 'Test Offer ' . Str::random(5),
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
     * @param array<int, array{service: Service, qty: int}> $items
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
