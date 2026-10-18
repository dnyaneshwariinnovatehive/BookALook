<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\Cart;
use App\Models\CartItem;
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

class AdminAsServiceProviderTest extends TestCase
{
    use DatabaseTransactions;

    private User $admin;
    private Salon $salon;
    private User $customer;
    private Service $service1;
    private Service $service2;
    private string $unique;

    protected function setUp(): void
    {
        parent::setUp();

        $this->unique = substr(bin2hex(random_bytes(6)), 0, 8);

        // 1. Create Admin User
        $this->admin = User::create([
            'id' => (string) Str::uuid(),
            'name' => "Admin {$this->unique}",
            'phone' => '91' . substr((string) crc32($this->unique . 'adm'), 0, 8),
            'password_hash' => bcrypt('password'),
            'role' => 'admin',
            'is_active' => true,
        ]);

        // 2. Create Active Salon
        $this->salon = Salon::create([
            'id' => (string) Str::uuid(),
            'admin_id' => $this->admin->id,
            'name' => "Salon {$this->unique}",
            'slug' => "salon-{$this->unique}",
            'address' => '123 Market Street',
            'submitted_by' => $this->admin->id,
            'status' => 'active',
        ]);

        // 3. Create Customer
        $this->customer = User::create([
            'id' => (string) Str::uuid(),
            'name' => "Customer {$this->unique}",
            'phone' => '92' . substr((string) crc32($this->unique . 'cust'), 0, 8),
            'password_hash' => bcrypt('password'),
            'role' => 'customer',
            'is_active' => true,
        ]);

        // 4. Ensure an active subscription plan exists for the salon so salon.active passes
        $plan = SubscriptionPlan::first() ?? SubscriptionPlan::create([
            'id' => (string) Str::uuid(),
            'name' => 'Growth Plan',
            'price' => 999.00,
            'duration_days' => 30,
            'is_active' => true,
        ]);

        SalonSubscription::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salon->id,
            'plan_id' => $plan->id,
            'billing_type' => \App\Support\BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => $plan->price,
            'start_date' => Carbon::today()->subDays(5),
            'end_date' => Carbon::today()->addDays(25),
            'status' => 'active',
        ]);

        // 5. Ensure 7 salon working hours exist
        for ($i = 0; $i < 7; $i++) {
            SalonWorkingHour::create([
                'id' => (string) Str::uuid(),
                'salon_id' => $this->salon->id,
                'day_of_week' => $i,
                'is_closed' => false,
                'open_time' => '09:00:00',
                'close_time' => '20:00:00',
            ]);
        }

        // 6. Create ServiceCategory, Templates, and Services
        $category = ServiceCategory::firstOrCreate(
            ['name' => 'Hair Care'],
            ['id' => (string) Str::uuid(), 'is_active' => true]
        );

        $template1 = ServiceTemplate::firstOrCreate(
            ['name' => "Haircut {$this->unique}"],
            [
                'id' => (string) Str::uuid(),
                'category_id' => $category->id,
                'is_active' => true,
                'gender' => 'unisex',
                'estimated_duration_minutes' => 30,
            ]
        );

        $template2 = ServiceTemplate::firstOrCreate(
            ['name' => "Beard Trim {$this->unique}"],
            [
                'id' => (string) Str::uuid(),
                'category_id' => $category->id,
                'is_active' => true,
                'gender' => 'male',
                'estimated_duration_minutes' => 30,
            ]
        );

        $this->service1 = Service::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salon->id,
            'template_id' => $template1->id,
            'price' => 250.00,
            'duration_minutes' => 30,
            'is_active' => true,
        ]);

        $this->service2 = Service::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salon->id,
            'template_id' => $template2->id,
            'price' => 150.00,
            'duration_minutes' => 30,
            'is_active' => true,
        ]);
    }

    public function test_admin_can_enable_provider_mode_without_changing_user_role(): void
    {
        $response = $this->actingAs($this->admin)
            ->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", [
                'enabled' => true,
                'specialization' => 'Owner & Master Barber',
                'service_ids' => [$this->service1->id],
                'use_salon_hours' => true,
            ]);

        $response->assertStatus(200);
        $response->assertJson([
            'is_provider_enabled' => true,
            'provider' => [
                'user_id' => $this->admin->id,
                'salon_id' => $this->salon->id,
                'specialization' => 'Owner & Master Barber',
                'is_active' => true,
            ],
        ]);

        // CRITICAL BOUNDARY: users.role MUST remain 'admin'
        $this->admin->refresh();
        $this->assertSame('admin', $this->admin->role);

        // Verify provider record exists
        $provider = ServiceProvider::where('user_id', $this->admin->id)->first();
        $this->assertNotNull($provider);
        $this->assertSame($this->salon->id, $provider->salon_id);
        $this->assertTrue((bool) $provider->is_active);
    }

    public function test_repeated_activation_is_idempotent_and_does_not_create_duplicates(): void
    {
        // First activation
        $this->actingAs($this->admin)
            ->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", [
                'enabled' => true,
                'specialization' => 'Owner',
            ])->assertStatus(200);

        $countBefore = ServiceProvider::withTrashed()->where('user_id', $this->admin->id)->count();
        $this->assertSame(1, $countBefore);

        // Second activation (idempotent)
        $this->actingAs($this->admin)
            ->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", [
                'enabled' => true,
                'specialization' => 'Owner & Senior Stylist',
            ])->assertStatus(200);

        $countAfter = ServiceProvider::withTrashed()->where('user_id', $this->admin->id)->count();
        $this->assertSame(1, $countAfter);
    }

    public function test_previously_soft_deleted_provider_record_is_restored_safely(): void
    {
        // First create and soft-delete
        $provider = ServiceProvider::create([
            'id' => (string) Str::uuid(),
            'user_id' => $this->admin->id,
            'salon_id' => $this->salon->id,
            'specialization' => 'Original Stylist',
            'base_salary' => 0.00,
            'commission_percentage' => 0.00,
            'is_active' => false,
        ]);
        $provider->delete();

        $this->assertTrue($provider->fresh()->trashed());

        // Toggle activation
        $response = $this->actingAs($this->admin)
            ->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", [
                'enabled' => true,
                'specialization' => 'Restored Stylist',
            ]);

        $response->assertStatus(200);
        $restored = ServiceProvider::withTrashed()->where('user_id', $this->admin->id)->first();
        $this->assertNotNull($restored);
        $this->assertFalse($restored->trashed());
        $this->assertTrue((bool) $restored->is_active);
    }

    public function test_only_salon_owner_can_manage_admin_provider_settings(): void
    {
        $otherAdmin = User::create([
            'id' => (string) Str::uuid(),
            'name' => "Other Admin {$this->unique}",
            'phone' => '93' . substr((string) crc32($this->unique . 'other'), 0, 8),
            'password_hash' => bcrypt('password'),
            'role' => 'admin',
            'is_active' => true,
        ]);
        $customer = $this->customer;

        // Other admin
        $this->actingAs($otherAdmin)
            ->getJson("/api/partner/salons/{$this->salon->id}/admin-provider")
            ->assertStatus(403);

        $this->actingAs($otherAdmin)
            ->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", ['enabled' => true])
            ->assertStatus(403);

        // Customer
        $this->actingAs($customer)
            ->getJson("/api/partner/salons/{$this->salon->id}/admin-provider")
            ->assertStatus(403);
    }

    public function test_service_assignments_and_schedule_changes_persist_correctly(): void
    {
        // Enable with both services and custom hours
        $customHours = [];
        for ($i = 0; $i < 7; $i++) {
            $customHours[] = [
                'day_of_week' => $i,
                'is_weekly_off' => $i === 0, // Sunday off
                'shift_start' => $i === 0 ? null : '10:00:00',
                'shift_end' => $i === 0 ? null : '19:00:00',
                'break_start' => null,
                'break_end' => null,
            ];
        }

        $response = $this->actingAs($this->admin)
            ->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", [
                'enabled' => true,
                'service_ids' => [$this->service1->id, $this->service2->id],
                'working_hours' => $customHours,
            ]);

        $response->assertStatus(200);
        $provider = ServiceProvider::where('user_id', $this->admin->id)->first();
        $this->assertCount(2, $provider->services);
        $this->assertCount(7, $provider->workingHours);

        $sunday = $provider->workingHours->firstWhere('day_of_week', 0);
        $monday = $provider->workingHours->firstWhere('day_of_week', 1);
        $this->assertTrue((bool) $sunday->is_weekly_off);
        $this->assertSame('10:00:00', $monday->shift_start);

        // Switch to use_salon_hours
        $this->actingAs($this->admin)
            ->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", [
                'enabled' => true,
                'use_salon_hours' => true,
            ])->assertStatus(200);

        $provider->refresh();
        $mondayUpdated = $provider->workingHours->firstWhere('day_of_week', 1);
        $this->assertSame('09:00:00', $mondayUpdated->shift_start);
    }

    public function test_setup_status_correctly_reports_missing_schedule_and_services(): void
    {
        // Enable without services and without hours
        $provider = ServiceProvider::withTrashed()->firstOrNew(['user_id' => $this->admin->id]);
        $provider->id = $provider->id ?? (string) Str::uuid();
        $provider->salon_id = $this->salon->id;
        $provider->is_active = true;
        $provider->save();
        $provider->services()->detach();
        ProviderWorkingHour::where('provider_id', $provider->id)->delete();

        $response = $this->actingAs($this->admin)
            ->getJson("/api/partner/salons/{$this->salon->id}/admin-provider");

        $response->assertStatus(200);
        $response->assertJson([
            'is_provider_enabled' => true,
            'setup_validation' => [
                'salon_hours_configured' => true,
                'admin_hours_configured' => false,
                'services_assigned' => false,
                'is_ready_for_booking' => false,
            ],
        ]);
    }

    public function test_customer_provider_listing_includes_or_excludes_admin(): void
    {
        // 1. When provider mode is disabled
        $this->actingAs($this->admin)
            ->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", [
                'enabled' => false,
            ])->assertStatus(200);

        // Create active cart for customer
        $this->createCustomerCart([$this->service1->id]);

        $response = $this->actingAs($this->customer)
            ->getJson("/api/customer/salons/{$this->salon->id}/providers");

        $response->assertStatus(200);
        $providerIds = collect($response->json('providers'))->pluck('id')->all();
        $adminProvider = ServiceProvider::withTrashed()->where('user_id', $this->admin->id)->first();
        if ($adminProvider) {
            $this->assertNotContains($adminProvider->id, $providerIds);
        }

        // 2. When provider mode is enabled with service1 only
        $this->actingAs($this->admin)
            ->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", [
                'enabled' => true,
                'service_ids' => [$this->service1->id],
                'use_salon_hours' => true,
            ])->assertStatus(200);

        $adminProvider = ServiceProvider::where('user_id', $this->admin->id)->first();

        // Check providers with cart containing service1
        $response = $this->actingAs($this->customer)
            ->getJson("/api/customer/salons/{$this->salon->id}/providers");
        $providers = collect($response->json('providers'));
        $adminEntry = $providers->firstWhere('id', $adminProvider->id);
        $this->assertNotNull($adminEntry);
        $this->assertTrue($adminEntry['is_eligible']);

        // Check providers with cart containing service2 (which Admin does not perform)
        $this->createCustomerCart([$this->service2->id]);
        $response = $this->actingAs($this->customer)
            ->getJson("/api/customer/salons/{$this->salon->id}/providers");
        $providers = collect($response->json('providers'));
        $adminEntry = $providers->firstWhere('id', $adminProvider->id);
        $this->assertNotNull($adminEntry);
        $this->assertFalse($adminEntry['is_eligible'], 'Admin should be marked ineligible when missing requested service');
    }

    public function test_ineligible_and_disabled_admin_provider_ids_are_rejected(): void
    {
        // Enable with service1 only
        $this->actingAs($this->admin)
            ->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", [
                'enabled' => true,
                'service_ids' => [$this->service1->id],
                'use_salon_hours' => true,
            ]);

        $adminProvider = ServiceProvider::where('user_id', $this->admin->id)->first();

        // 1. Try to book service2 with admin (ineligible)
        $this->createCustomerCart([$this->service2->id]);
        $tomorrow = Carbon::tomorrow()->toDateString();
        $this->actingAs($this->customer)
            ->postJson("/api/customer/salons/{$this->salon->id}/appointments/book", [
                'date' => $tomorrow,
                'time' => '11:00',
                'provider_id' => $adminProvider->id,
            ])
            ->assertStatus(422);

        // 2. Disable admin provider mode
        $this->actingAs($this->admin)
            ->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", [
                'enabled' => false,
            ]);

        // Try to book service1 with disabled admin
        $this->createCustomerCart([$this->service1->id]);
        $this->actingAs($this->customer)
            ->postJson("/api/customer/salons/{$this->salon->id}/appointments/book", [
                'date' => $tomorrow,
                'time' => '11:00',
                'provider_id' => $adminProvider->id,
            ])
            ->assertStatus(422);
    }

    public function test_disabling_preserves_appointments_and_warns_with_future_bookings(): void
    {
        // Enable admin provider
        $this->actingAs($this->admin)
            ->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", [
                'enabled' => true,
                'service_ids' => [$this->service1->id],
                'use_salon_hours' => true,
            ]);
        $provider = ServiceProvider::where('user_id', $this->admin->id)->first();

        // Create an upcoming appointment for the admin
        $appointment = Appointment::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salon->id,
            'customer_id' => $this->customer->id,
            'appointed_provider_id' => $provider->id,
            'booking_source' => 'online',
            'appointment_date' => Carbon::tomorrow()->toDateString(),
            'start_time' => '14:00:00',
            'end_time' => '14:30:00',
            'status' => 'scheduled',
            'payment_option' => 'advance',
            'total_amount' => 250.00,
            'advance_amount' => 62.50,
            'balance_amount' => 187.50,
        ]);

        // Check status includes upcoming_appointments_count >= 1
        $statusRes = $this->actingAs($this->admin)
            ->getJson("/api/partner/salons/{$this->salon->id}/admin-provider");
        $statusRes->assertStatus(200);
        $this->assertGreaterThanOrEqual(1, $statusRes->json('upcoming_appointments_count'));

        // Disable provider mode
        $toggleRes = $this->actingAs($this->admin)
            ->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", [
                'enabled' => false,
            ]);
        $toggleRes->assertStatus(200);
        $toggleRes->assertJson(['is_provider_enabled' => false]);

        // Verify appointment was NOT deleted or cancelled
        $this->assertDatabaseHas('appointments', [
            'id' => $appointment->id,
            'status' => 'scheduled',
            'appointed_provider_id' => $provider->id,
        ]);

        // Verify provider record still exists with is_active = false
        $provider->refresh();
        $this->assertFalse((bool) $provider->is_active);
        $this->assertFalse($provider->trashed());
    }

    public function test_admin_personal_appointments_query_filter(): void
    {
        // Enable admin provider
        $this->actingAs($this->admin)
            ->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", [
                'enabled' => true,
                'service_ids' => [$this->service1->id],
                'use_salon_hours' => true,
            ]);
        $adminProvider = ServiceProvider::where('user_id', $this->admin->id)->first();

        // Create another staff provider
        $otherStaffUser = User::create([
            'id' => (string) Str::uuid(),
            'name' => "Staff {$this->unique}",
            'phone' => '94' . substr((string) crc32($this->unique . 'staff'), 0, 8),
            'password_hash' => bcrypt('password'),
            'role' => 'service_provider',
            'is_active' => true,
        ]);
        $otherProvider = ServiceProvider::create([
            'id' => (string) Str::uuid(),
            'user_id' => $otherStaffUser->id,
            'salon_id' => $this->salon->id,
            'specialization' => 'Barber',
            'base_salary' => 0,
            'commission_percentage' => 0,
            'is_active' => true,
        ]);

        $date = Carbon::tomorrow()->toDateString();

        // 1. Appointment for Admin
        $aptAdmin = Appointment::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salon->id,
            'customer_id' => $this->customer->id,
            'appointed_provider_id' => $adminProvider->id,
            'booking_source' => 'online',
            'appointment_date' => $date,
            'start_time' => '10:00:00',
            'end_time' => '10:30:00',
            'status' => 'scheduled',
            'total_amount' => 250,
            'advance_amount' => 60,
            'balance_amount' => 190,
        ]);

        // 2. Appointment for other staff
        $aptOther = Appointment::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salon->id,
            'customer_id' => $this->customer->id,
            'appointed_provider_id' => $otherProvider->id,
            'booking_source' => 'online',
            'appointment_date' => $date,
            'start_time' => '11:00:00',
            'end_time' => '11:30:00',
            'status' => 'scheduled',
            'total_amount' => 250,
            'advance_amount' => 60,
            'balance_amount' => 190,
        ]);

        // Query with provider_id = adminProvider->id (My Appointments)
        $response = $this->actingAs($this->admin)
            ->getJson("/api/partner/salons/{$this->salon->id}/appointments?date={$date}&provider_id={$adminProvider->id}");

        $response->assertStatus(200);
        $ids = collect($response->json('appointments'))->pluck('id')->all();
        $this->assertContains($aptAdmin->id, $ids);
        $this->assertNotContains($aptOther->id, $ids);

        // Query without provider_id (Salon Schedule)
        $responseAll = $this->actingAs($this->admin)
            ->getJson("/api/partner/salons/{$this->salon->id}/appointments?date={$date}");
        $allIds = collect($responseAll->json('appointments'))->pluck('id')->all();
        $this->assertContains($aptAdmin->id, $allIds);
        $this->assertContains($aptOther->id, $allIds);
    }

    public function test_staff_management_destroy_protects_admin_provider_profile(): void
    {
        // Enable admin provider
        $this->actingAs($this->admin)
            ->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", [
                'enabled' => true,
            ]);
        $adminProvider = ServiceProvider::where('user_id', $this->admin->id)->first();

        // Attempting to delete via regular staff destroy route
        $response = $this->actingAs($this->admin)
            ->deleteJson("/api/partner/salons/{$this->salon->id}/staff/{$adminProvider->id}");

        $response->assertStatus(422);
        $response->assertJsonFragment([
            'message' => 'The salon owner provider profile cannot be deleted as ordinary staff. Please use the "Also work as a service provider" toggle to deactivate it.',
        ]);

        $this->assertDatabaseHas('service_providers', [
            'id' => $adminProvider->id,
            'user_id' => $this->admin->id,
        ]);
    }

    private function createCustomerCart(array $serviceIds): void
    {
        Cart::where('customer_id', $this->customer->id)->where('salon_id', $this->salon->id)->delete();
        $cart = Cart::create([
            'id' => (string) Str::uuid(),
            'customer_id' => $this->customer->id,
            'salon_id' => $this->salon->id,
            'status' => 'active',
        ]);
        foreach ($serviceIds as $sid) {
            CartItem::create([
                'id' => (string) Str::uuid(),
                'cart_id' => $cart->id,
                'service_id' => $sid,
                'quantity' => 1,
            ]);
        }
    }
}
