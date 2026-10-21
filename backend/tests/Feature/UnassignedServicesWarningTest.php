<?php

namespace Tests\Feature;

use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceProvider;
use App\Models\ServiceTemplate;
use App\Models\SubscriptionPlan;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class UnassignedServicesWarningTest extends TestCase
{
    use DatabaseTransactions;

    private User $admin;
    private Salon $salon;
    private ServiceCategory $category;
    private Service $service1;
    private Service $service2;
    private Service $service3;
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

        // 3. Ensure Salon has an active subscription for salon.active middleware
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
            'start_date' => \Carbon\Carbon::today()->subDays(5),
            'end_date' => \Carbon\Carbon::today()->addDays(25),
            'status' => 'active',
        ]);

        // 4. Create Category & Service Templates
        $this->category = ServiceCategory::create([
            'id' => (string) Str::uuid(),
            'name' => "Hair Care {$this->unique}",
            'is_custom' => false,
            'is_active' => true,
        ]);

        $template1 = ServiceTemplate::create([
            'id' => (string) Str::uuid(),
            'category_id' => $this->category->id,
            'name' => 'Haircut Classic',
            'estimated_duration_minutes' => 30,
            'is_custom' => false,
            'is_active' => true,
        ]);

        $template2 = ServiceTemplate::create([
            'id' => (string) Str::uuid(),
            'category_id' => $this->category->id,
            'name' => 'Hair Coloring',
            'estimated_duration_minutes' => 60,
            'is_custom' => false,
            'is_active' => true,
        ]);

        $template3 = ServiceTemplate::create([
            'id' => (string) Str::uuid(),
            'category_id' => $this->category->id,
            'name' => 'Keratin Treatment',
            'estimated_duration_minutes' => 90,
            'is_custom' => false,
            'is_active' => true,
        ]);

        // 5. Create Services for Salon
        $this->service1 = Service::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salon->id,
            'template_id' => $template1->id,
            'price' => 350.00,
            'is_active' => true,
            'display_order' => 1,
        ]);

        $this->service2 = Service::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salon->id,
            'template_id' => $template2->id,
            'price' => 1200.00,
            'is_active' => true,
            'display_order' => 2,
        ]);

        $this->service3 = Service::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salon->id,
            'template_id' => $template3->id,
            'price' => 2500.00,
            'is_active' => true,
            'display_order' => 3,
        ]);
    }

    public function test_all_services_unassigned_initially(): void
    {
        Sanctum::actingAs($this->admin);

        // Check services endpoint
        $res = $this->getJson("/api/partner/salons/{$this->salon->id}/services");
        $res->assertStatus(200);
        $res->assertJsonCount(3, 'unassigned_services');

        $unassignedIds = collect($res->json('unassigned_services'))->pluck('id')->all();
        $this->assertContains($this->service1->id, $unassignedIds);
        $this->assertContains($this->service2->id, $unassignedIds);
        $this->assertContains($this->service3->id, $unassignedIds);

        // Check staff endpoint
        $resStaff = $this->getJson("/api/partner/salons/{$this->salon->id}/staff");
        $resStaff->assertStatus(200);
        $resStaff->assertJsonCount(3, 'unassigned_services');

        // Check direct unassigned endpoint
        $resUnassigned = $this->getJson("/api/partner/salons/{$this->salon->id}/unassigned-services");
        $resUnassigned->assertStatus(200);
        $resUnassigned->assertJsonCount(3, 'unassigned_services');
    }

    public function test_service_assigned_to_regular_staff_is_no_longer_unassigned(): void
    {
        Sanctum::actingAs($this->admin);

        // Create a regular staff member
        $staffUser = User::create([
            'id' => (string) Str::uuid(),
            'name' => 'Stylist Jane',
            'phone' => '91' . substr((string) crc32($this->unique . 'stf1'), 0, 8),
            'password_hash' => bcrypt('password'),
            'role' => 'service_provider',
            'is_active' => true,
        ]);

        $provider = ServiceProvider::create([
            'id' => (string) Str::uuid(),
            'user_id' => $staffUser->id,
            'salon_id' => $this->salon->id,
            'specialization' => 'Senior Hair Stylist',
            'is_active' => true,
        ]);

        // Assign service1 to this staff member
        $provider->services()->sync([$this->service1->id]);

        $res = $this->getJson("/api/partner/salons/{$this->salon->id}/services");
        $res->assertStatus(200);
        $res->assertJsonCount(2, 'unassigned_services');

        $unassignedIds = collect($res->json('unassigned_services'))->pluck('id')->all();
        $this->assertNotContains($this->service1->id, $unassignedIds);
        $this->assertContains($this->service2->id, $unassignedIds);
        $this->assertContains($this->service3->id, $unassignedIds);
    }

    public function test_admin_provider_mode_counts_towards_service_assignment(): void
    {
        Sanctum::actingAs($this->admin);

        // Admin enables Provider Mode and assigns service2 and service3
        $toggleRes = $this->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", [
            'enabled' => true,
            'specialization' => 'Master Stylist & Owner',
            'service_ids' => [$this->service2->id, $this->service3->id],
        ]);
        $toggleRes->assertStatus(200);

        // Now only service1 should be unassigned
        $res = $this->getJson("/api/partner/salons/{$this->salon->id}/services");
        $res->assertStatus(200);
        $res->assertJsonCount(1, 'unassigned_services');
        $this->assertEquals($this->service1->id, $res->json('unassigned_services.0.id'));

        // If Admin turns off Provider Mode:
        $toggleOffRes = $this->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", [
            'enabled' => false,
        ]);
        $toggleOffRes->assertStatus(200);

        // Now service2 and service3 become unassigned again!
        $resAfter = $this->getJson("/api/partner/salons/{$this->salon->id}/services");
        $resAfter->assertStatus(200);
        $resAfter->assertJsonCount(3, 'unassigned_services');
    }

    public function test_all_services_covered_warning_disappears(): void
    {
        Sanctum::actingAs($this->admin);

        // Create staff covering service1 and service2
        $staffUser = User::create([
            'id' => (string) Str::uuid(),
            'name' => 'Stylist Mike',
            'phone' => '91' . substr((string) crc32($this->unique . 'stf2'), 0, 8),
            'password_hash' => bcrypt('password'),
            'role' => 'service_provider',
            'is_active' => true,
        ]);

        $provider = ServiceProvider::create([
            'id' => (string) Str::uuid(),
            'user_id' => $staffUser->id,
            'salon_id' => $this->salon->id,
            'is_active' => true,
        ]);
        $provider->services()->sync([$this->service1->id, $this->service2->id]);

        // Admin provider mode covers service3
        $this->postJson("/api/partner/salons/{$this->salon->id}/admin-provider/toggle", [
            'enabled' => true,
            'service_ids' => [$this->service3->id],
        ]);

        // All 3 services are covered!
        $res = $this->getJson("/api/partner/salons/{$this->salon->id}/services");
        $res->assertStatus(200);
        $res->assertJsonCount(0, 'unassigned_services');

        $resStaff = $this->getJson("/api/partner/salons/{$this->salon->id}/staff");
        $resStaff->assertStatus(200);
        $resStaff->assertJsonCount(0, 'unassigned_services');
    }

    public function test_inactive_or_deleted_staff_does_not_count_as_covered(): void
    {
        Sanctum::actingAs($this->admin);

        $staffUser = User::create([
            'id' => (string) Str::uuid(),
            'name' => 'Inactive Staff',
            'phone' => '91' . substr((string) crc32($this->unique . 'stf3'), 0, 8),
            'password_hash' => bcrypt('password'),
            'role' => 'service_provider',
            'is_active' => false,
        ]);

        $provider = ServiceProvider::create([
            'id' => (string) Str::uuid(),
            'user_id' => $staffUser->id,
            'salon_id' => $this->salon->id,
            'is_active' => false, // deactivated
        ]);
        $provider->services()->sync([$this->service1->id]);

        // Service 1 was only assigned to an inactive provider, so it must still be unassigned
        $res = $this->getJson("/api/partner/salons/{$this->salon->id}/services");
        $res->assertStatus(200);
        $unassignedIds = collect($res->json('unassigned_services'))->pluck('id')->all();
        $this->assertContains($this->service1->id, $unassignedIds);
    }

    public function test_assign_service_staff_assigns_to_staff_and_admin_provider_correctly(): void
    {
        Sanctum::actingAs($this->admin);

        // 1. Regular staff
        $staffUser = User::create([
            'id' => (string) Str::uuid(),
            'name' => 'Stylist Sarah',
            'phone' => '91' . substr((string) crc32($this->unique . 'sarah'), 0, 8),
            'password_hash' => bcrypt('password'),
            'role' => 'service_provider',
            'is_active' => true,
        ]);
        $staffProvider = ServiceProvider::create([
            'id' => (string) Str::uuid(),
            'user_id' => $staffUser->id,
            'salon_id' => $this->salon->id,
            'specialization' => 'Hair Specialist',
            'is_active' => true,
        ]);

        // 2. Admin provider enabled
        $adminProvider = ServiceProvider::create([
            'id' => (string) Str::uuid(),
            'user_id' => $this->admin->id,
            'salon_id' => $this->salon->id,
            'specialization' => 'Owner & Master Stylist',
            'is_active' => true,
        ]);

        // 3. Fetch staff for unassigned service1
        $resStaff = $this->getJson("/api/partner/salons/{$this->salon->id}/services/{$this->service1->id}/staff");
        $resStaff->assertStatus(200);
        $allStaff = $resStaff->json('all_staff');
        $this->assertCount(2, $allStaff);

        // Verify admin is flagged as admin provider
        $adminItem = collect($allStaff)->firstWhere('user_id', $this->admin->id);
        $this->assertNotNull($adminItem);
        $this->assertTrue($adminItem['is_admin_provider']);

        $staffItem = collect($allStaff)->firstWhere('user_id', $staffUser->id);
        $this->assertNotNull($staffItem);
        $this->assertFalse($staffItem['is_admin_provider']);

        // 4. Assign both to service1
        $assignRes = $this->postJson("/api/partner/salons/{$this->salon->id}/services/{$this->service1->id}/staff", [
            'staff_ids' => [$staffProvider->id, $adminProvider->id],
        ]);
        $assignRes->assertStatus(200);

        // Verify service1 is in both providers' skillset
        $this->assertTrue($staffProvider->fresh()->services->contains('id', $this->service1->id));
        $this->assertTrue($adminProvider->fresh()->services->contains('id', $this->service1->id));

        // Verify service1 is no longer unassigned
        $resAfter = $this->getJson("/api/partner/salons/{$this->salon->id}/services");
        $resAfter->assertStatus(200);
        $unassignedIds = collect($resAfter->json('unassigned_services'))->pluck('id')->all();
        $this->assertNotContains($this->service1->id, $unassignedIds);
    }
}
