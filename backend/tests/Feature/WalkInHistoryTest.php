<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\AppointmentService;
use App\Models\City;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceProvider;
use App\Models\ServiceTemplate;
use App\Models\SubscriptionPlan;
use App\Models\SubArea;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class WalkInHistoryTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;
    private User $providerUser;
    private ServiceProvider $provider;
    private Salon $salon;
    private Service $service;

    protected function setUp(): void
    {
        parent::setUp();

        $city = City::create(['name' => 'Mumbai', 'state' => 'Maharashtra', 'is_active' => true]);
        $subArea = SubArea::create(['name' => 'Andheri', 'city_id' => $city->id, 'is_active' => true]);

        $this->admin = User::create([
            'role' => 'admin',
            'name' => 'Salon Owner',
            'phone' => '9820000001',
            'password_hash' => bcrypt('password'),
        ]);

        $this->salon = Salon::create([
            'admin_id' => $this->admin->id,
            'city_id' => $city->id,
            'sub_area_id' => $subArea->id,
            'name' => 'Elite Salon',
            'slug' => 'elite-salon-' . Str::random(6),
            'address' => '123 Main Street',
            'status' => 'active',
            'submitted_by' => $this->admin->id,
        ]);

        $plan = SubscriptionPlan::create([
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

        $this->providerUser = User::create([
            'role' => 'service_provider',
            'name' => 'Stylist Jane',
            'phone' => '9820000002',
            'password_hash' => bcrypt('password'),
        ]);

        $this->provider = ServiceProvider::create([
            'user_id' => $this->providerUser->id,
            'salon_id' => $this->salon->id,
            'specialization' => 'Hair Specialist',
            'commission_percentage' => 10,
            'is_active' => true,
        ]);

        $category = ServiceCategory::create([
            'name' => 'Hair Care',
            'is_active' => true,
        ]);

        $template = ServiceTemplate::create([
            'category_id' => $category->id,
            'name' => 'Haircut & Styling',
            'estimated_duration_minutes' => 45,
            'is_active' => true,
        ]);

        $this->service = Service::create([
            'salon_id' => $this->salon->id,
            'template_id' => $template->id,
            'price' => 500,
            'is_active' => true,
        ]);

        $this->provider->services()->attach($this->service->id);
    }

    public function test_admin_can_view_walk_in_history_and_summary_metrics(): void
    {
        // 1 completed walk-in today
        $apt1 = Appointment::create([
            'salon_id' => $this->salon->id,
            'appointed_provider_id' => $this->provider->id,
            'serving_provider_id' => $this->provider->id,
            'booking_source' => 'walk_in',
            'walk_in_customer_name' => 'Rahul Sharma',
            'walk_in_customer_phone' => '9811122233',
            'walk_in_customer_gender' => 'Male',
            'appointment_date' => Carbon::today()->toDateString(),
            'start_time' => '10:00:00',
            'end_time' => '10:45:00',
            'status' => 'completed',
            'total_amount' => 500,
            'final_billed_amount' => 500,
            'balance_amount' => 0,
            'payment_mode' => 'cash',
            'payment_collected_at' => now(),
            'payment_collected_by' => $this->admin->id,
            'started_at' => now()->subHour(),
            'completed_at' => now(),
        ]);

        AppointmentService::create([
            'appointment_id' => $apt1->id,
            'service_id' => $this->service->id,
            'serving_provider_id' => $this->provider->id,
            'price_at_booking' => 500,
            'original_service_price' => 500,
            'duration_minutes_at_booking' => 45,
            'line_status' => 'completed',
        ]);

        // 1 in_progress walk-in today
        $apt2 = Appointment::create([
            'salon_id' => $this->salon->id,
            'appointed_provider_id' => $this->provider->id,
            'serving_provider_id' => $this->provider->id,
            'booking_source' => 'walk_in',
            'walk_in_customer_name' => 'Priya Patel',
            'walk_in_customer_phone' => '9844455566',
            'walk_in_customer_gender' => 'Female',
            'appointment_date' => Carbon::today()->toDateString(),
            'start_time' => '12:00:00',
            'end_time' => '12:45:00',
            'status' => 'in_progress',
            'total_amount' => 500,
            'balance_amount' => 500,
            'started_at' => now(),
        ]);

        AppointmentService::create([
            'appointment_id' => $apt2->id,
            'service_id' => $this->service->id,
            'serving_provider_id' => $this->provider->id,
            'price_at_booking' => 500,
            'original_service_price' => 500,
            'duration_minutes_at_booking' => 45,
            'line_status' => 'booked',
        ]);

        $response = $this->actingAs($this->admin, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salon->id}/walk-in/history")
            ->assertStatus(200)
            ->assertJsonStructure([
                'summary' => [
                    'total_walk_ins',
                    'today_walk_ins',
                    'in_progress',
                    'completed',
                    'total_revenue',
                ],
                'walk_ins',
                'pagination',
                'viewer',
            ]);

        $data = $response->json();
        $this->assertEquals(2, $data['summary']['total_walk_ins']);
        $this->assertEquals(2, $data['summary']['today_walk_ins']);
        $this->assertEquals(1, $data['summary']['in_progress']);
        $this->assertEquals(1, $data['summary']['completed']);
        $this->assertEquals(500.0, $data['summary']['total_revenue']);
        $this->assertCount(2, $data['walk_ins']);

        // Check details of first walk-in
        $item = collect($data['walk_ins'])->firstWhere('id', $apt1->id);
        $this->assertNotNull($item);
        $this->assertEquals('Rahul Sharma', $item['customer_name']);
        $this->assertEquals('9811122233', $item['customer_phone']);
        $this->assertEquals('Male', $item['customer_gender']);
        $this->assertEquals('completed', $item['status']);
        $this->assertEquals('cash', $item['payment_mode']);
        $this->assertEquals('Salon Owner', $item['payment_collected_by_name']);
        $this->assertNotEmpty($item['services']);
        $this->assertEquals('Haircut & Styling', $item['services'][0]['name']);
        $this->assertEquals('Stylist Jane', $item['serving_provider']['name']);
    }

    public function test_search_and_filters_work(): void
    {
        Appointment::create([
            'salon_id' => $this->salon->id,
            'appointed_provider_id' => $this->provider->id,
            'booking_source' => 'walk_in',
            'walk_in_customer_name' => 'Aarav Mehta',
            'walk_in_customer_phone' => '9988776655',
            'appointment_date' => Carbon::today()->toDateString(),
            'start_time' => '10:00:00',
            'end_time' => '10:45:00',
            'status' => 'completed',
            'total_amount' => 500,
        ]);

        Appointment::create([
            'salon_id' => $this->salon->id,
            'appointed_provider_id' => $this->provider->id,
            'booking_source' => 'walk_in',
            'walk_in_customer_name' => 'Sneha Kulkarni',
            'walk_in_customer_phone' => '9123456789',
            'appointment_date' => Carbon::yesterday()->toDateString(),
            'start_time' => '14:00:00',
            'end_time' => '14:45:00',
            'status' => 'cancelled',
            'total_amount' => 500,
        ]);

        // Search by name
        $searchRes = $this->actingAs($this->admin, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salon->id}/walk-in/history?search=Sneha")
            ->assertStatus(200)
            ->json();
        $this->assertCount(1, $searchRes['walk_ins']);
        $this->assertEquals('Sneha Kulkarni', $searchRes['walk_ins'][0]['customer_name']);

        // Filter by date=today
        $dateRes = $this->actingAs($this->admin, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salon->id}/walk-in/history?date=today")
            ->assertStatus(200)
            ->json();
        $this->assertCount(1, $dateRes['walk_ins']);
        $this->assertEquals('Aarav Mehta', $dateRes['walk_ins'][0]['customer_name']);

        // Filter by status=cancelled
        $statusRes = $this->actingAs($this->admin, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salon->id}/walk-in/history?status=cancelled")
            ->assertStatus(200)
            ->json();
        $this->assertCount(1, $statusRes['walk_ins']);
        $this->assertEquals('Sneha Kulkarni', $statusRes['walk_ins'][0]['customer_name']);
    }

    public function test_service_provider_can_access_history(): void
    {
        Appointment::create([
            'salon_id' => $this->salon->id,
            'appointed_provider_id' => $this->provider->id,
            'serving_provider_id' => $this->provider->id,
            'booking_source' => 'walk_in',
            'walk_in_customer_name' => 'Test Walkin',
            'appointment_date' => Carbon::today()->toDateString(),
            'start_time' => '10:00:00',
            'end_time' => '10:45:00',
            'status' => 'completed',
            'total_amount' => 500,
        ]);

        $this->actingAs($this->providerUser, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salon->id}/walk-in/history")
            ->assertStatus(200)
            ->assertJsonPath('viewer.role', 'service_provider');
    }

    public function test_unauthorized_user_cannot_view_history(): void
    {
        $outsider = User::create([
            'role' => 'customer',
            'name' => 'Random Person',
            'phone' => '9999999999',
            'password_hash' => bcrypt('password'),
        ]);

        $this->actingAs($outsider, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salon->id}/walk-in/history")
            ->assertStatus(403);
    }

    /**
     * The history eager-loads a few named invoice columns. SQLite reads an
     * unknown double-quoted name as a string instead of failing, so a typo
     * there (`total_amount` for `total`) passed here and broke the whole
     * history on PostgreSQL. Pin the names to the real table.
     */
    public function test_the_invoice_columns_it_reads_exist(): void
    {
        $this->assertTrue(
            \Illuminate\Support\Facades\Schema::hasColumns('invoices', ['id', 'appointment_id', 'invoice_number', 'total', 'pdf_url'])
        );
    }
}
