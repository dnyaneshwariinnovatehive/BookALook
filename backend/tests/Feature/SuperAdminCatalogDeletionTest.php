<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\AppointmentService;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\City;
use App\Models\Invoice;
use App\Models\Salon;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceProvider;
use App\Models\ServiceTemplate;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class SuperAdminCatalogDeletionTest extends TestCase
{
    use RefreshDatabase;
    use \Tests\Feature\Concerns\ActivatesSalons;

    private User $superAdmin;
    private User $regularCustomer;
    private User $salonOwner;
    private Salon $salon;
    private City $city;

    protected function setUp(): void
    {
        parent::setUp();

        $this->superAdmin = User::create([
            'role' => 'superadmin',
            'phone' => '9000000001',
            'name' => 'Super Admin',
            'email' => 'superadmin@example.com',
            'password_hash' => bcrypt('password'),
        ]);

        $this->regularCustomer = User::create([
            'role' => 'customer',
            'phone' => '9000000002',
            'name' => 'Customer User',
            'email' => 'customer@example.com',
            'password_hash' => bcrypt('password'),
        ]);

        $this->salonOwner = User::create([
            'role' => 'admin',
            'phone' => '9000000003',
            'name' => 'Salon Owner',
            'email' => 'owner@example.com',
            'password_hash' => bcrypt('password'),
        ]);

        $this->city = City::create([
            'name' => 'Mumbai',
            'state' => 'Maharashtra',
            'is_active' => true,
        ]);

        $this->salon = Salon::create([
            'name' => 'Hair Studio Mumbai',
            'slug' => 'hair-studio-mumbai',
            'city_id' => $this->city->id,
            'admin_id' => $this->salonOwner->id,
            'submitted_by' => $this->salonOwner->id,
            'address' => 'Linking Road, Bandra West',
            'pincode' => '400050',
            'gender_focus' => 'Unisex',
            'status' => 'approved',
        ]);
    }

    private function createCategory(string $name = 'Hair Care'): ServiceCategory
    {
        return ServiceCategory::create([
            'name' => $name,
            'icon_url' => 'https://example.com/icon.png',
            'is_custom' => false,
            'is_active' => true,
            'display_order' => 1,
        ]);
    }

    private function createTemplate(ServiceCategory $category, string $name = 'Classic Haircut'): ServiceTemplate
    {
        return ServiceTemplate::create([
            'category_id' => $category->id,
            'name' => $name,
            'estimated_duration_minutes' => 30,
            'is_custom' => false,
            'is_active' => true,
        ]);
    }

    private function createService(Salon $salon, ServiceTemplate $template, float $price = 500.00): Service
    {
        return Service::create([
            'salon_id' => $salon->id,
            'template_id' => $template->id,
            'price' => $price,
            'advance_percentage' => 20.00,
            'is_active' => true,
            'gender_focus' => 'Unisex',
        ]);
    }

    /**
     * Case 1: Retiring a template with no linked salon services.
     */
    public function test_01_retiring_template_with_no_linked_salon_services()
    {
        $category = $this->createCategory();
        $template = $this->createTemplate($category, 'Standalone Template');

        $response = $this->actingAs($this->superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/templates/{$template->id}");

        $response->assertStatus(200);
        $response->assertJson([
            'message' => 'Service template retired successfully'
        ]);

        // Template is soft-deleted
        $this->assertSoftDeleted('service_templates', ['id' => $template->id]);
        $this->assertDatabaseHas('service_templates', ['id' => $template->id, 'is_active' => false]);
    }

    /**
     * Case 2: Retiring a template referenced by active salon services.
     */
    public function test_02_retiring_template_referenced_by_active_salon_services()
    {
        $category = $this->createCategory();
        $template = $this->createTemplate($category, 'Cut & Wash');
        $service = $this->createService($this->salon, $template, 600.00);

        $response = $this->actingAs($this->superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/templates/{$template->id}");

        $response->assertStatus(200);

        // Template and linked service are soft-deleted and deactivated
        $this->assertSoftDeleted('service_templates', ['id' => $template->id]);
        $this->assertSoftDeleted('services', ['id' => $service->id]);
        $this->assertDatabaseHas('services', ['id' => $service->id, 'is_active' => false]);
    }

    /**
     * Case 3: Retiring a template referenced by soft-deleted salon services.
     */
    public function test_03_retiring_template_referenced_by_already_soft_deleted_salon_services()
    {
        $category = $this->createCategory();
        $template = $this->createTemplate($category, 'Beard Trim');
        $service = $this->createService($this->salon, $template, 300.00);
        $service->delete(); // Already soft-deleted previously by salon

        $response = $this->actingAs($this->superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/templates/{$template->id}");

        $response->assertStatus(200);
        $this->assertSoftDeleted('service_templates', ['id' => $template->id]);
        $this->assertSoftDeleted('services', ['id' => $service->id]);
    }

    /**
     * Case 4: Retiring a template whose service has existing appointment history.
     */
    public function test_04_retiring_template_with_appointment_history_preserves_records()
    {
        $category = $this->createCategory();
        $template = $this->createTemplate($category, 'Bridal Hair');
        $service = $this->createService($this->salon, $template, 2500.00);

        $staffUser = User::create([
            'role' => 'staff',
            'phone' => '9000000004',
            'name' => 'Stylist Staff',
            'password_hash' => bcrypt('password'),
        ]);

        $provider = ServiceProvider::create([
            'salon_id' => $this->salon->id,
            'user_id' => $staffUser->id,
            'is_active' => true,
        ]);

        $appointment = Appointment::create([
            'salon_id' => $this->salon->id,
            'customer_id' => $this->regularCustomer->id,
            'appointed_provider_id' => $provider->id,
            'appointment_date' => '2026-10-24',
            'start_time' => '10:00:00',
            'end_time' => '10:30:00',
            'status' => 'completed',
            'total_amount' => 2500.00,
            'advance_amount' => 500.00,
            'balance_amount' => 2000.00,
            'booking_source' => 'online',
        ]);

        $apptService = AppointmentService::create([
            'appointment_id' => $appointment->id,
            'service_id' => $service->id,
            'price_at_booking' => 2500.00,
            'original_service_price' => 2500.00,
            'duration_minutes_at_booking' => 30,
            'line_status' => 'completed',
        ]);

        // Execute template retirement
        $response = $this->actingAs($this->superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/templates/{$template->id}");

        $response->assertStatus(200);

        // Historical appointment, appointment_services, and service records are 100% intact
        $this->assertDatabaseHas('appointments', ['id' => $appointment->id]);
        $this->assertDatabaseHas('appointment_services', ['id' => $apptService->id]);

        // Historical relationships resolve cleanly through withTrashed
        $refreshedAppt = Appointment::with(['services.service.template.category'])->find($appointment->id);
        $this->assertNotNull($refreshedAppt);
        $this->assertEquals('Bridal Hair', $refreshedAppt->services->first()->service->template->name);
        $this->assertEquals($category->name, $refreshedAppt->services->first()->service->template->category->name);
    }

    /**
     * Case 5: Retiring a category containing multiple templates.
     */
    public function test_05_retiring_category_containing_multiple_templates()
    {
        $category = $this->createCategory('Spa & Wellness');
        $tpl1 = $this->createTemplate($category, 'Swedish Massage');
        $tpl2 = $this->createTemplate($category, 'Deep Tissue Massage');

        $svc1 = $this->createService($this->salon, $tpl1, 1500.00);
        $svc2 = $this->createService($this->salon, $tpl2, 2000.00);

        $response = $this->actingAs($this->superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/categories/{$category->id}");

        $response->assertStatus(200);
        $response->assertJson([
            'message' => 'Category and associated templates retired successfully'
        ]);

        $this->assertSoftDeleted('service_categories', ['id' => $category->id]);
        $this->assertSoftDeleted('service_templates', ['id' => $tpl1->id]);
        $this->assertSoftDeleted('service_templates', ['id' => $tpl2->id]);
        $this->assertSoftDeleted('services', ['id' => $svc1->id]);
        $this->assertSoftDeleted('services', ['id' => $svc2->id]);
    }

    /**
     * Case 6: Retiring a category whose templates are used by multiple salons.
     */
    public function test_06_retiring_category_used_by_multiple_salons()
    {
        $salon2 = Salon::create([
            'name' => 'Second Salon Pune',
            'slug' => 'second-salon-pune',
            'city_id' => $this->city->id,
            'admin_id' => $this->salonOwner->id,
            'submitted_by' => $this->salonOwner->id,
            'address' => 'FC Road, Pune',
            'pincode' => '411004',
            'gender_focus' => 'Unisex',
            'status' => 'approved',
        ]);

        $category = $this->createCategory('Skin Care');
        $tpl = $this->createTemplate($category, 'Gold Facial');

        $svcSalon1 = $this->createService($this->salon, $tpl, 1200.00);
        $svcSalon2 = $this->createService($salon2, $tpl, 1400.00);

        $response = $this->actingAs($this->superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/categories/{$category->id}");

        $response->assertStatus(200);

        $this->assertSoftDeleted('services', ['id' => $svcSalon1->id]);
        $this->assertSoftDeleted('services', ['id' => $svcSalon2->id]);
        $this->assertSoftDeleted('service_templates', ['id' => $tpl->id]);
        $this->assertSoftDeleted('service_categories', ['id' => $category->id]);
    }

    /**
     * Case 7: Retiring an empty category.
     */
    public function test_07_retiring_empty_category()
    {
        $category = $this->createCategory('Empty Category');

        $response = $this->actingAs($this->superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/categories/{$category->id}");

        $response->assertStatus(200);
        $this->assertSoftDeleted('service_categories', ['id' => $category->id]);
    }

    /**
     * Case 8: Attempting to retire a nonexistent category or template.
     */
    public function test_08_retiring_nonexistent_category_or_template_returns_404()
    {
        $fakeUuid = (string) \Illuminate\Support\Str::uuid();

        $resCat = $this->actingAs($this->superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/categories/{$fakeUuid}");
        $resCat->assertStatus(404);
        $resCat->assertJson(['message' => 'Category not found']);

        $resTpl = $this->actingAs($this->superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/templates/{$fakeUuid}");
        $resTpl->assertStatus(404);
        $resTpl->assertJson(['message' => 'Service template not found']);
    }

    /**
     * Case 9: Unauthorized deletion attempts.
     */
    public function test_09_unauthorized_deletion_attempts_are_blocked()
    {
        $category = $this->createCategory();
        $template = $this->createTemplate($category);

        // Unauthenticated
        $this->deleteJson("/api/superadmin/catalog/templates/{$template->id}")
            ->assertStatus(401);

        // Customer role
        $this->actingAs($this->regularCustomer, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/templates/{$template->id}")
            ->assertStatus(403);

        $this->actingAs($this->regularCustomer, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/categories/{$category->id}")
            ->assertStatus(403);
    }

    /**
     * Case 10: Transaction rollback when a dependent operation fails.
     */
    public function test_10_transaction_rollback_when_operation_fails()
    {
        $category = $this->createCategory('Rollback Category');
        $template = $this->createTemplate($category, 'Rollback Template');
        $service = $this->createService($this->salon, $template, 700.00);

        // Simulate a database failure during transaction by breaking on ServiceCategory deleting event
        ServiceCategory::deleting(function () {
            throw new \RuntimeException('Simulated catastrophic failure during category retirement');
        });

        $response = $this->actingAs($this->superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/categories/{$category->id}");

        $response->assertStatus(500);

        // Confirm rollback: none of the records should be deleted or deactivated
        $this->assertDatabaseHas('service_categories', ['id' => $category->id, 'deleted_at' => null]);
        $this->assertDatabaseHas('service_templates', ['id' => $template->id, 'deleted_at' => null]);
        $this->assertDatabaseHas('services', ['id' => $service->id, 'deleted_at' => null, 'is_active' => true]);
    }

    /**
     * Case 11: Repeated deletion requests and already-retired records.
     */
    public function test_11_repeated_deletion_requests_return_404_cleanly()
    {
        $category = $this->createCategory();
        $template = $this->createTemplate($category, 'Once Template');

        // First deletion
        $this->actingAs($this->superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/templates/{$template->id}")
            ->assertStatus(200);

        // Repeated deletion attempt on the same ID
        $this->actingAs($this->superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/templates/{$template->id}")
            ->assertStatus(404);
    }

    /**
     * Case 12: Ensuring retired catalog items no longer appear in customer/partner discovery.
     */
    public function test_12_retired_catalog_items_do_not_appear_in_discovery_or_partner_catalog()
    {
        $category = $this->createCategory('Active Category');
        $template = $this->createTemplate($category, 'Active Template');
        $this->createService($this->salon, $template, 500.00);

        // Verify it appears before retirement
        $catRes = $this->getJson('/api/customer/categories');
        $catRes->assertStatus(200);
        $this->assertTrue(collect($catRes->json('categories'))->contains('id', $category->id));

        // Retire category
        $this->actingAs($this->superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/categories/{$category->id}")
            ->assertStatus(200);

        // Excluded from Customer categories
        $catResAfter = $this->getJson('/api/customer/categories');
        $catResAfter->assertStatus(200);
        $this->assertFalse(collect($catResAfter->json('categories'))->contains('id', $category->id));

        // Set salon status to active and create active subscription so salon.active middleware passes for partner
        $this->salon->update(['status' => 'active']);

        $plan = \App\Models\SubscriptionPlan::create([
            'name' => 'Growth Plan',
            'price' => 999.00,
            'duration_days' => 30,
            'is_active' => true,
        ]);

        \App\Models\SalonSubscription::create([
            'salon_id' => $this->salon->id,
            'plan_id' => $plan->id,
            'billing_type' => \App\Support\BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => $plan->price,
            'start_date' => now()->subDay()->toDateString(),
            'end_date' => now()->addDays(30)->toDateString(),
            'status' => 'active',
        ]);

        // Excluded from Partner master catalog
        $partnerRes = $this->actingAs($this->salonOwner, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salon->id}/master-catalog");
        $partnerRes->assertStatus(200);
        $this->assertFalse(collect($partnerRes->json('categories'))->contains('id', $category->id));
    }

    /**
     * Case 13: Ensuring retired services cannot be booked through direct API requests or stale carts.
     */
    public function test_13_retired_services_cannot_be_booked_and_stale_carts_are_gracefully_handled()
    {
        $category = $this->createCategory('Nail Art');
        $tplRetired = $this->createTemplate($category, 'Gel Nails');
        $tplActive = $this->createTemplate($category, 'Regular Polish');

        $svcRetired = $this->createService($this->salon, $tplRetired, 800.00);
        $svcActive = $this->createService($this->salon, $tplActive, 400.00);

        // Only a live salon (active, on an in-date plan) takes bookings.
        $this->salon->update(['status' => 'active']);
        $this->activateSalon($this->salon);

        // 1. Customer adds both to cart
        $cart = Cart::create([
            'customer_id' => $this->regularCustomer->id,
            'salon_id' => $this->salon->id,
            'status' => 'active',
        ]);
        $itemRetired = CartItem::create([
            'cart_id' => $cart->id,
            'service_id' => $svcRetired->id,
            'quantity' => 1,
        ]);
        $itemActive = CartItem::create([
            'cart_id' => $cart->id,
            'service_id' => $svcActive->id,
            'quantity' => 1,
        ]);

        // 2. SuperAdmin retires the Gel Nails template
        $this->actingAs($this->superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/templates/{$tplRetired->id}")
            ->assertStatus(200);

        // 3. Attempting to add retired service directly fails
        $addRes = $this->actingAs($this->regularCustomer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/cart/items", [
                'service_id' => $svcRetired->id,
            ]);
        $addRes->assertStatus(422);
        $addRes->assertJson(['message' => 'This service is no longer available.']);

        // 4. Customer attempts to book with stale cart
        $staffUser = User::create([
            'role' => 'staff',
            'phone' => '9000000005',
            'name' => 'Provider 5',
            'password_hash' => bcrypt('password'),
        ]);
        $provider = ServiceProvider::create([
            'salon_id' => $this->salon->id,
            'user_id' => $staffUser->id,
            'is_active' => true,
        ]);

        $bookRes = $this->actingAs($this->regularCustomer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/appointments/book", [
                'date' => now()->addDays(2)->format('Y-m-d'),
                'time' => '11:00',
                'provider_id' => $provider->id,
            ]);

        // Booking fails gracefully, explains issue, and removes ONLY the retired item
        $bookRes->assertStatus(422);
        $bookRes->assertJson([
            'retired_items_removed' => true,
        ]);
        $this->assertStringContainsString('Gel Nails', $bookRes->json('message'));

        // Retired item was deleted from cart; active item remains in cart!
        $this->assertDatabaseMissing('cart_items', ['id' => $itemRetired->id]);
        $this->assertDatabaseHas('cart_items', ['id' => $itemActive->id]);
    }

    /**
     * Case 14: Ensuring historical appointments and invoices remain accessible and unchanged.
     */
    public function test_14_historical_appointments_and_invoices_remain_accessible_after_retirement()
    {
        $category = $this->createCategory('Permanent Makeup');
        $template = $this->createTemplate($category, 'Microblading');
        $service = $this->createService($this->salon, $template, 5000.00);

        $staffUser = User::create([
            'role' => 'staff',
            'phone' => '9000000006',
            'name' => 'Artist Staff',
            'password_hash' => bcrypt('password'),
        ]);
        $provider = ServiceProvider::create([
            'salon_id' => $this->salon->id,
            'user_id' => $staffUser->id,
            'is_active' => true,
        ]);

        $appointment = Appointment::create([
            'salon_id' => $this->salon->id,
            'customer_id' => $this->regularCustomer->id,
            'appointed_provider_id' => $provider->id,
            'appointment_date' => '2026-10-15',
            'start_time' => '15:00:00',
            'end_time' => '16:00:00',
            'status' => 'completed',
            'total_amount' => 5000.00,
            'advance_amount' => 1000.00,
            'balance_amount' => 4000.00,
            'final_billed_amount' => 5000.00,
            'payment_mode' => 'online',
            'booking_source' => 'online',
        ]);

        AppointmentService::create([
            'appointment_id' => $appointment->id,
            'service_id' => $service->id,
            'price_at_booking' => 5000.00,
            'original_service_price' => 5000.00,
            'duration_minutes_at_booking' => 60,
            'line_status' => 'completed',
        ]);

        Invoice::create([
            'appointment_id' => $appointment->id,
            'invoice_number' => 'INV-2026-TEST-001',
            'issued_at' => now(),
            'salon_name' => $this->salon->name,
            'bill_to_name' => $this->regularCustomer->name,
            'appointment_date' => '2026-10-15',
            'start_time' => '15:00:00',
            'end_time' => '16:00:00',
            'line_items' => [
                ['name' => 'Microblading', 'price' => 5000.00, 'quantity' => 1]
            ],
            'subtotal' => 5000.00,
            'total' => 5000.00,
            'template' => ['title' => 'Tax Invoice'],
        ]);

        // Retire category & template
        $this->actingAs($this->superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/categories/{$category->id}")
            ->assertStatus(200);

        // Fetch customer appointments API
        $res = $this->actingAs($this->regularCustomer, 'sanctum')
            ->getJson("/api/customer/appointments/{$appointment->id}");

        $res->assertStatus(200);
        $res->assertJson([
            'appointment' => [
                'id' => $appointment->id,
                'status' => 'completed',
                'total_amount' => 5000.00,
            ]
        ]);

        // Verify line item name still displays 'Microblading' in API response
        $lines = $res->json('appointment.services');
        $this->assertNotEmpty($lines);
        $this->assertEquals('Microblading', $lines[0]['name']);

        // Verify underlying Eloquent relationships still resolve with withTrashed
        $refreshed = Appointment::with('services.service.template.category')->find($appointment->id);
        $this->assertEquals('Microblading', $refreshed->services->first()->service->template->name);
        $this->assertEquals('Permanent Makeup', $refreshed->services->first()->service->template->category->name);
    }

    /**
     * Case 15: Verifying SuperAdmin catalog index excludes retired items without requiring reload.
     */
    public function test_15_superadmin_catalog_index_excludes_retired_categories_and_templates()
    {
        $category = $this->createCategory('Active Hair');
        $template1 = $this->createTemplate($category, 'Shampoo');
        $template2 = $this->createTemplate($category, 'Blowdry');

        // Initially both templates and category are present
        $indexRes = $this->actingAs($this->superAdmin, 'sanctum')
            ->getJson('/api/superadmin/catalog');
        $indexRes->assertStatus(200);
        $cats = collect($indexRes->json('categories'));
        $foundCat = $cats->firstWhere('id', $category->id);
        $this->assertNotNull($foundCat);
        $this->assertCount(2, $foundCat['templates']);

        // Retire template 1
        $this->actingAs($this->superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/templates/{$template1->id}")
            ->assertStatus(200);

        // Index now has only template 2
        $indexRes2 = $this->actingAs($this->superAdmin, 'sanctum')
            ->getJson('/api/superadmin/catalog');
        $cats2 = collect($indexRes2->json('categories'));
        $foundCat2 = $cats2->firstWhere('id', $category->id);
        $this->assertNotNull($foundCat2);
        $this->assertCount(1, $foundCat2['templates']);
        $this->assertEquals('Blowdry', $foundCat2['templates'][0]['name']);

        // Retire category
        $this->actingAs($this->superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/catalog/categories/{$category->id}")
            ->assertStatus(200);

        // Index now excludes the entire category
        $indexRes3 = $this->actingAs($this->superAdmin, 'sanctum')
            ->getJson('/api/superadmin/catalog');
        $cats3 = collect($indexRes3->json('categories'));
        $this->assertNull($cats3->firstWhere('id', $category->id));
    }
}
