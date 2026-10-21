<?php

namespace Tests\Feature;

use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceTemplate;
use App\Models\SubscriptionPlan;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AddServiceDuplicateAndAdvanceTest extends TestCase
{
    use DatabaseTransactions;

    private User $admin;
    private Salon $salon;
    private ServiceCategory $category;
    private ServiceTemplate $template;
    private string $unique;

    protected function setUp(): void
    {
        parent::setUp();

        $this->unique = substr(bin2hex(random_bytes(6)), 0, 8);

        $this->admin = User::create([
            'id' => (string) Str::uuid(),
            'name' => "Admin {$this->unique}",
            'phone' => '91' . substr((string) crc32($this->unique . 'adm'), 0, 8),
            'password_hash' => bcrypt('password'),
            'role' => 'admin',
            'is_active' => true,
        ]);

        $this->salon = Salon::create([
            'id' => (string) Str::uuid(),
            'admin_id' => $this->admin->id,
            'name' => "Salon {$this->unique}",
            'slug' => "salon-{$this->unique}",
            'address' => '123 Market Street',
            'submitted_by' => $this->admin->id,
            'status' => 'active',
        ]);

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

        $this->category = ServiceCategory::create([
            'id' => (string) Str::uuid(),
            'name' => "Hair Care {$this->unique}",
            'is_custom' => false,
            'is_active' => true,
        ]);

        $this->template = ServiceTemplate::create([
            'id' => (string) Str::uuid(),
            'category_id' => $this->category->id,
            'name' => "Men's Haircut",
            'estimated_duration_minutes' => 30,
            'is_custom' => false,
            'is_active' => true,
        ]);
    }

    public function test_cannot_add_duplicate_service_by_template_id(): void
    {
        Sanctum::actingAs($this->admin);

        // First creation succeeds
        $res1 = $this->postJson("/api/partner/salons/{$this->salon->id}/services", [
            'is_custom' => false,
            'template_id' => $this->template->id,
            'price' => 350,
            'advance_percentage' => 20,
            'will_refund_advance_if_cancelled' => true,
        ]);
        $res1->assertStatus(200);

        // Second creation with the same template_id is rejected
        $res2 = $this->postJson("/api/partner/salons/{$this->salon->id}/services", [
            'is_custom' => false,
            'template_id' => $this->template->id,
            'price' => 400,
            'advance_percentage' => 20,
        ]);
        $res2->assertStatus(400);
        $res2->assertJsonFragment(['message' => 'This service already exists in this salon']);
    }

    public function test_cannot_add_custom_service_with_same_name_as_existing(): void
    {
        Sanctum::actingAs($this->admin);

        // Add standard service Men's Haircut
        Service::create([
            'salon_id' => $this->salon->id,
            'template_id' => $this->template->id,
            'price' => 300,
            'is_active' => true,
        ]);

        // Attempt to create custom service with name "men's haircut "
        $res = $this->postJson("/api/partner/salons/{$this->salon->id}/services", [
            'is_custom' => true,
            'category_id' => $this->category->id,
            'custom_template_name' => "  men's haircut  ",
            'estimated_duration_minutes' => 30,
            'price' => 400,
            'advance_percentage' => 20,
        ]);
        $res->assertStatus(400);
        $res->assertJsonFragment(['message' => 'A service with this name already exists in this salon']);
    }

    public function test_cannot_enable_refund_when_advance_percentage_is_zero(): void
    {
        Sanctum::actingAs($this->admin);

        $res = $this->postJson("/api/partner/salons/{$this->salon->id}/services", [
            'is_custom' => false,
            'template_id' => $this->template->id,
            'price' => 250,
            'advance_percentage' => 0,
            'will_refund_advance_if_cancelled' => true,
        ]);
        $res->assertStatus(422);
        $res->assertJsonFragment(['message' => 'Refund advance cannot be enabled when minimum advance is 0%.']);
    }

    public function test_refund_is_disabled_and_stored_as_false_when_advance_percentage_is_zero(): void
    {
        Sanctum::actingAs($this->admin);

        $res = $this->postJson("/api/partner/salons/{$this->salon->id}/services", [
            'is_custom' => false,
            'template_id' => $this->template->id,
            'price' => 250,
            'advance_percentage' => 0,
            'will_refund_advance_if_cancelled' => false,
        ]);
        $res->assertStatus(200);

        $service = Service::where('salon_id', $this->salon->id)->where('template_id', $this->template->id)->first();
        $this->assertNotNull($service);
        $this->assertEquals(0, (float) $service->advance_percentage);
        $this->assertFalse((bool) $service->will_refund_advance_if_cancelled);
    }

    public function test_refund_is_allowed_when_advance_percentage_is_greater_than_zero(): void
    {
        Sanctum::actingAs($this->admin);

        $res = $this->postJson("/api/partner/salons/{$this->salon->id}/services", [
            'is_custom' => false,
            'template_id' => $this->template->id,
            'price' => 500,
            'advance_percentage' => 25,
            'will_refund_advance_if_cancelled' => true,
        ]);
        $res->assertStatus(200);

        $service = Service::where('salon_id', $this->salon->id)->where('template_id', $this->template->id)->first();
        $this->assertNotNull($service);
        $this->assertEquals(25, (float) $service->advance_percentage);
        $this->assertTrue((bool) $service->will_refund_advance_if_cancelled);
    }
}
