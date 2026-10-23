<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\AppointmentService;
use App\Models\City;
use App\Models\Complaint;
use App\Models\Salon;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceProvider;
use App\Models\ServiceTemplate;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SuperAdminComplaintDetailsTest extends TestCase
{
    use RefreshDatabase;

    public function test_superadmin_complaint_show_returns_rich_customer_salon_and_appointment_details()
    {
        $adminUser = User::create([
            'role' => 'admin',
            'phone' => '9999999999',
            'name' => 'Salon Owner',
            'email' => 'owner@example.com',
            'password_hash' => bcrypt('password'),
        ]);

        $superAdmin = User::create([
            'role' => 'superadmin',
            'phone' => '9000000000',
            'name' => 'Super Administrator',
            'email' => 'superadmin@example.com',
            'password_hash' => bcrypt('password'),
        ]);

        $customer = User::create([
            'role' => 'customer',
            'name' => 'Priya Sharma',
            'phone' => '9876543210',
            'email' => 'priya@example.com',
            'password_hash' => bcrypt('password'),
        ]);

        $city = City::create(['name' => 'Pune', 'state' => 'Maharashtra', 'is_active' => true]);

        $salon = Salon::create([
            'name' => 'Luxe Glamour Salon',
            'slug' => 'luxe-glamour-salon',
            'city_id' => $city->id,
            'admin_id' => $adminUser->id,
            'submitted_by' => $adminUser->id,
            'address' => '102 MG Road, Camp, Pune',
            'pincode' => '411001',
            'gender_focus' => 'Unisex',
            'status' => 'approved',
            'commission_opt_in' => true,
            'commission_percentage' => 15.00,
        ]);

        $category = ServiceCategory::create(['name' => 'Hair', 'icon' => 'hair.png', 'is_active' => true]);
        $template = ServiceTemplate::create([
            'category_id' => $category->id,
            'name' => 'Premium Hair Spa',
            'duration_minutes' => 45,
            'gender' => 'Unisex',
            'is_active' => true,
        ]);

        $service = Service::create([
            'salon_id' => $salon->id,
            'template_id' => $template->id,
            'price' => 1200.00,
            'is_active' => true,
        ]);

        $staffUser = User::create([
            'name' => 'Rohan Staff',
            'phone' => '9111111111',
            'role' => 'staff',
            'password_hash' => bcrypt('password'),
        ]);
        $provider = ServiceProvider::create([
            'salon_id' => $salon->id,
            'user_id' => $staffUser->id,
            'is_active' => true,
        ]);

        $appointment = Appointment::create([
            'salon_id' => $salon->id,
            'customer_id' => $customer->id,
            'appointed_provider_id' => $provider->id,
            'serving_provider_id' => $provider->id,
            'appointment_date' => '2026-10-20',
            'start_time' => '14:00:00',
            'end_time' => '14:45:00',
            'status' => 'completed',
            'payment_mode' => 'online',
            'booking_source' => 'app',
            'total_amount' => 1200.00,
            'advance_amount' => 300.00,
            'balance_amount' => 900.00,
            'final_billed_amount' => 1200.00,
            'verification_method' => 'otp',
        ]);

        AppointmentService::create([
            'appointment_id' => $appointment->id,
            'service_id' => $service->id,
            'price_at_booking' => 1200.00,
            'original_service_price' => 1200.00,
            'duration_minutes_at_booking' => 45,
            'serving_provider_id' => $provider->id,
            'line_status' => 'completed',
        ]);

        $complaint = Complaint::create([
            'salon_id' => $salon->id,
            'customer_id' => $customer->id,
            'related_appointment_id' => $appointment->id,
            'subject' => 'Service was rushed',
            'description' => 'The staff member finished in 20 minutes instead of 45 minutes.',
            'status' => Complaint::STATUS_OPEN,
        ]);

        $response = $this->actingAs($superAdmin, 'sanctum')
            ->getJson("/api/superadmin/complaints/{$complaint->id}");

        $response->assertStatus(200);
        $response->assertJson([
            'success' => true,
            'data' => [
                'id' => $complaint->id,
                'subject' => 'Service was rushed',
                'customer_name' => 'Priya Sharma',
                'salon_name' => 'Luxe Glamour Salon',
            ],
            'customer_details' => [
                'name' => 'Priya Sharma',
                'phone' => '9876543210',
                'email' => 'priya@example.com',
                'total_platform_bookings' => 1,
                'salon_visits_count' => 1,
                'past_complaints_count' => 0,
            ],
            'salon_details' => [
                'name' => 'Luxe Glamour Salon',
                'status' => 'approved',
                'city_name' => 'Pune',
                'contact_phone' => '9999999999',
                'contact_email' => 'owner@example.com',
                'owner_name' => 'Salon Owner',
                'commercial_model' => 'commission',
                'commission_percentage' => 15.00,
            ],
            'appointment_details' => [
                'status' => 'completed',
                'total_amount' => 1200.00,
                'advance_paid_amount' => 300.00,
                'balance_amount' => 900.00,
                'appointed_provider_name' => 'Rohan Staff',
                'verification_method' => 'otp',
                'services' => [
                    [
                        'name' => 'Premium Hair Spa',
                        'price' => 1200.00,
                        'duration_minutes' => 45,
                        'serving_provider_name' => 'Rohan Staff',
                        'line_status' => 'completed',
                    ]
                ],
            ],
        ]);
    }
}
