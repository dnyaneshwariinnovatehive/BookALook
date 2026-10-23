<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\City;
use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Models\SubArea;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class BusinessInsightsRealDataTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;
    private Salon $salon;
    private ServiceProvider $provider;
    private User $providerUser;

    protected function setUp(): void
    {
        parent::setUp();

        $city = City::create(['name' => 'Pune', 'state' => 'Maharashtra', 'is_active' => true]);
        $subArea = SubArea::create(['name' => 'Kothrud', 'city_id' => $city->id, 'is_active' => true]);

        $this->admin = User::create([
            'role' => 'admin',
            'name' => 'Salon Owner Admin',
            'phone' => '9820000001',
            'password_hash' => bcrypt('password'),
        ]);

        $this->salon = Salon::create([
            'admin_id' => $this->admin->id,
            'city_id' => $city->id,
            'sub_area_id' => $subArea->id,
            'name' => 'Prestige Hair Studio',
            'slug' => 'prestige-hair-' . Str::random(6),
            'address' => 'FC Road, Pune',
            'status' => 'active',
            'submitted_by' => $this->admin->id,
        ]);

        $this->providerUser = User::create([
            'role' => 'service_provider',
            'name' => 'Rahul Sharma',
            'phone' => '9820000002',
            'password_hash' => bcrypt('password'),
        ]);

        $this->provider = ServiceProvider::create([
            'user_id' => $this->providerUser->id,
            'salon_id' => $this->salon->id,
            'is_active' => true,
        ]);
    }

    public function test_admin_gets_real_insights_with_revenue_trend_staff_and_retention_funnel(): void
    {
        // Customer 1: Ramesh (2 visits)
        // Visit 1: 5 days ago (W4)
        Appointment::create([
            'salon_id' => $this->salon->id,
            'appointed_provider_id' => $this->provider->id,
            'serving_provider_id' => $this->provider->id,
            'booking_source' => 'walk_in',
            'appointment_date' => Carbon::now()->subDays(5)->toDateString(),
            'start_time' => '10:00:00',
            'end_time' => '10:45:00',
            'status' => 'completed',
            'total_amount' => 500,
            'final_billed_amount' => 500,
            'walk_in_customer_name' => 'Ramesh Kumar',
            'walk_in_customer_phone' => '9876543210',
        ]);

        // Visit 2: 10 days ago (W3)
        Appointment::create([
            'salon_id' => $this->salon->id,
            'appointed_provider_id' => $this->provider->id,
            'serving_provider_id' => $this->provider->id,
            'booking_source' => 'online',
            'appointment_date' => Carbon::now()->subDays(10)->toDateString(),
            'start_time' => '14:00:00',
            'end_time' => '15:00:00',
            'status' => 'completed',
            'total_amount' => 800,
            'final_billed_amount' => 800,
            'walk_in_customer_name' => 'Ramesh Kumar',
            'walk_in_customer_phone' => '9876543210',
        ]);

        // Customer 2: Suresh (1 visit, 25 days ago (W1))
        Appointment::create([
            'salon_id' => $this->salon->id,
            'appointed_provider_id' => $this->provider->id,
            'serving_provider_id' => $this->provider->id,
            'booking_source' => 'walk_in',
            'appointment_date' => Carbon::now()->subDays(25)->toDateString(),
            'start_time' => '16:00:00',
            'end_time' => '17:00:00',
            'status' => 'completed',
            'total_amount' => 1200,
            'final_billed_amount' => 1200,
            'walk_in_customer_name' => 'Suresh Patil',
            'walk_in_customer_phone' => '9876543211',
        ]);

        $response = $this->actingAs($this->admin, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salon->id}/insights");

        $response->assertStatus(200);
        $response->assertJson([
            'success' => true,
            'data' => [
                'advanced' => true,
                'overview' => [
                    'customers' => 2,
                    'returning_customers' => 1,
                    'repeat_rate' => 50.0,
                    'revenue' => 2500.0,
                    'total_visits' => 3,
                ],
            ],
            'locked' => [],
        ]);

        $data = $response->json('data');

        // Basic analytics: 30-Day Revenue Trend
        $this->assertArrayHasKey('basic_analytics', $data);
        $trend = $data['basic_analytics']['revenue_trend'];
        $this->assertEquals(2500.0, $trend['total_revenue']);
        $this->assertEquals(3, $trend['total_bookings']);
        $this->assertCount(4, $trend['weeks']);

        // Basic analytics: Staff Performance
        $staff = $data['basic_analytics']['staff_performance'];
        $this->assertNotEmpty($staff);
        $this->assertEquals('Rahul Sharma', $staff[0]['name']);
        $this->assertEquals(3, $staff[0]['bookings']);
        $this->assertEquals(2500.0, $staff[0]['revenue']);

        // Retention Funnel
        $this->assertArrayHasKey('retention_funnel', $data);
        $funnel = $data['retention_funnel'];
        $this->assertEquals(2, $funnel['total_customers']);
        $this->assertEquals(2, $funnel['first_visits']['count']);
        $this->assertEquals(100.0, $funnel['first_visits']['rate']);
        $this->assertEquals(1, $funnel['second_visits']['count']);
        $this->assertEquals(50.0, $funnel['second_visits']['rate']);
        $this->assertTrue($funnel['benchmark_is_good']);
        $this->assertStringContainsString('50%', $funnel['benchmark_message']);
    }

    public function test_admin_insights_when_no_appointments_exist(): void
    {
        $response = $this->actingAs($this->admin, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salon->id}/insights");

        $response->assertStatus(200);
        $data = $response->json('data');

        $this->assertEquals(0, $data['overview']['customers']);
        $this->assertEquals(0, $data['overview']['revenue']);
        $this->assertEquals(0, $data['basic_analytics']['revenue_trend']['total_revenue']);
        $this->assertEquals(0, $data['basic_analytics']['revenue_trend']['total_bookings']);
        $this->assertEquals(0, $data['retention_funnel']['total_customers']);
        $this->assertFalse($data['retention_funnel']['benchmark_is_good']);
        $this->assertEquals([], $response->json('locked'));
    }
}
