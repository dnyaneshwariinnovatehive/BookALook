<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\AppointmentService as AppointmentLine;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\ServiceProvider;
use App\Models\SubscriptionPlan;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * Audit and regression tests for live appointment visibility in Partner App.
 *
 * Verifies that:
 * 1. An appointment pending payment is hidden from partner schedule endpoints.
 * 2. As soon as payment confirms and status becomes 'scheduled', it appears
 *    immediately via GET /api/partner/salons/{salon_id}/appointments.
 * 3. Salon admin sees the newly scheduled appointment in the salon-wide schedule.
 * 4. Assigned provider sees it in their personal schedule.
 * 5. Unrelated provider cannot see another provider's personal appointments.
 * 6. Provider from another salon cannot access appointments (403 forbidden).
 * 7. Date and provider filters accurately scope results.
 */
class PartnerAppointmentVisibilityTest extends TestCase
{
    use DatabaseTransactions;

    public function test_pending_payment_appointment_is_hidden_from_partner_app(): void
    {
        [$salon, $admin, $customer, $provider] = $this->fixture();

        $appointment = $this->createAppointment($salon, $customer, $provider, [
            'status' => 'pending_payment',
            'payment_hold_expires_at' => now()->addMinutes(10),
        ]);

        // 1. Admin query must not return pending_payment
        $adminResponse = $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments")
            ->assertStatus(200)
            ->json('appointments');

        $adminIds = array_column($adminResponse, 'id');
        $this->assertNotContains($appointment->id, $adminIds, 'Admin should not see pending_payment appointments');

        // 2. Provider query must not return pending_payment
        $providerResponse = $this->actingAs($provider->user, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments")
            ->assertStatus(200)
            ->json('appointments');

        $providerIds = array_column($providerResponse, 'id');
        $this->assertNotContains($appointment->id, $providerIds, 'Provider should not see pending_payment appointments');
    }

    public function test_payment_confirmed_scheduled_appointment_is_immediately_visible(): void
    {
        [$salon, $admin, $customer, $provider, $other] = $this->fixture(needsSecondProvider: true);

        // 1. Initially held
        $appointment = $this->createAppointment($salon, $customer, $provider, [
            'status' => 'pending_payment',
            'payment_hold_expires_at' => now()->addMinutes(10),
        ]);

        // 2. Customer confirms payment -> status becomes 'scheduled'
        $appointment->forceFill([
            'status' => 'scheduled',
            'payment_hold_expires_at' => null,
        ])->save();

        // 3. Admin sees it in salon-wide schedule immediately
        $adminResponse = $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments")
            ->assertStatus(200)
            ->json('appointments');

        $adminIds = array_column($adminResponse, 'id');
        $this->assertContains($appointment->id, $adminIds, 'Admin must see newly scheduled appointment in salon schedule');

        // 4. Assigned provider sees it in their personal schedule
        $assignedResponse = $this->actingAs($provider->user, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments")
            ->assertStatus(200)
            ->json('appointments');

        $assignedIds = array_column($assignedResponse, 'id');
        $this->assertContains($appointment->id, $assignedIds, 'Assigned provider must see the appointment in their schedule');

        // 5. Unrelated provider cannot see another provider's personal appointment
        $otherResponse = $this->actingAs($other->user, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments")
            ->assertStatus(200)
            ->json('appointments');

        $otherIds = array_column($otherResponse, 'id');
        $this->assertNotContains($appointment->id, $otherIds, 'Unrelated provider must NOT see another provider appointments');
    }

    public function test_provider_from_another_salon_is_forbidden(): void
    {
        [$salonA, , , $providerA] = $this->fixture();
        [$salonB] = $this->fixture();

        // Provider A tries to access salon B's appointment endpoint
        $this->actingAs($providerA->user, 'sanctum')
            ->getJson("/api/partner/salons/{$salonB->id}/appointments")
            ->assertStatus(403);
    }

    public function test_filters_accurately_scope_appointments(): void
    {
        [$salon, $admin, $customer, $provider, $other] = $this->fixture(needsSecondProvider: true);

        $today = Carbon::today()->toDateString();
        $tomorrow = Carbon::tomorrow()->toDateString();

        $todayAppt = $this->createAppointment($salon, $customer, $provider, [
            'status' => 'scheduled',
            'appointment_date' => $today,
        ]);

        $tomorrowAppt = $this->createAppointment($salon, $customer, $other, [
            'status' => 'scheduled',
            'appointment_date' => $tomorrow,
        ]);

        // Filter by today's date
        $todayResponse = $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments?date={$today}")
            ->assertStatus(200)
            ->json('appointments');

        $todayIds = array_column($todayResponse, 'id');
        $this->assertContains($todayAppt->id, $todayIds);
        $this->assertNotContains($tomorrowAppt->id, $todayIds);

        // Filter by provider
        $providerResponse = $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments?provider_id={$provider->id}")
            ->assertStatus(200)
            ->json('appointments');

        $providerIds = array_column($providerResponse, 'id');
        $this->assertContains($todayAppt->id, $providerIds);
        $this->assertNotContains($tomorrowAppt->id, $providerIds);
    }

    // ------------------------------------------------------------- helpers

    /** @return array{0: Salon, 1: User, 2: User, 3: ServiceProvider, 4: ServiceProvider} */
    private function fixture(bool $needsSecondProvider = false): array
    {
        $admin = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Visibility Admin',
            'phone' => '98' . rand(10000000, 99999999),
            'password_hash' => bcrypt('password'),
            'role' => 'admin',
            'is_active' => true,
        ]);

        $salon = Salon::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'admin_id' => $admin->id,
            'name' => 'Visibility Test Salon',
            'slug' => 'visibility-test-salon-' . \Illuminate\Support\Str::random(5),
            'address' => '123 Visibility St',
            'status' => 'active',
            'submitted_by' => $admin->id,
        ]);

        $plan = SubscriptionPlan::firstOrCreate(
            ['name' => 'Visibility Test Plan'],
            [
                'id' => (string) \Illuminate\Support\Str::uuid(),
                'price' => 1000,
                'duration_days' => 30,
                'is_active' => true,
            ]
        );

        SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'billing_type' => \App\Support\BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => $plan->price,
            'start_date' => Carbon::today()->subDay(),
            'end_date' => Carbon::today()->addDays(30),
            'status' => 'active',
        ]);

        $customer = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Visibility Customer',
            'phone' => '97' . rand(10000000, 99999999),
            'password_hash' => bcrypt('password'),
            'role' => 'customer',
            'is_active' => true,
        ]);

        $providerUser1 = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Provider One',
            'phone' => '96' . rand(10000000, 99999999),
            'password_hash' => bcrypt('password'),
            'role' => 'service_provider',
            'is_active' => true,
        ]);

        $provider1 = ServiceProvider::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'user_id' => $providerUser1->id,
            'salon_id' => $salon->id,
            'is_active' => true,
        ]);

        $category = \App\Models\ServiceCategory::firstOrCreate(
            ['name' => 'Visibility Category'],
            ['id' => (string) \Illuminate\Support\Str::uuid(), 'is_active' => true]
        );
        $template = \App\Models\ServiceTemplate::firstOrCreate(
            ['name' => 'Visibility Service'],
            ['id' => (string) \Illuminate\Support\Str::uuid(), 'category_id' => $category->id, 'is_active' => true]
        );
        $service = \App\Models\Service::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'salon_id' => $salon->id,
            'template_id' => $template->id,
            'price' => 500,
            'duration_minutes' => 30,
            'advance_percentage' => 20,
            'is_active' => true,
        ]);
        $provider1->services()->attach($service->id);

        $providerUser2 = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Provider Two',
            'phone' => '95' . rand(10000000, 99999999),
            'password_hash' => bcrypt('password'),
            'role' => 'service_provider',
            'is_active' => true,
        ]);

        $provider2 = ServiceProvider::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'user_id' => $providerUser2->id,
            'salon_id' => $salon->id,
            'is_active' => true,
        ]);
        $provider2->services()->attach($service->id);

        return [
            $salon->fresh(),
            $admin->fresh(),
            $customer->fresh(),
            $provider1->fresh(['user', 'services']),
            $provider2->fresh(['user', 'services']),
        ];
    }

    private function createAppointment(Salon $salon, User $customer, ServiceProvider $provider, array $overrides = []): Appointment
    {
        $service = $provider->services->first();

        $appointment = Appointment::create(array_merge([
            'salon_id' => $salon->id,
            'customer_id' => $customer->id,
            'appointed_provider_id' => $provider->id,
            'booking_source' => 'online',
            'appointment_date' => Carbon::today()->toDateString(),
            'start_time' => '11:00:00',
            'end_time' => '11:30:00',
            'status' => 'scheduled',
            'payment_option' => 'advance_only',
            'total_amount' => 500,
            'advance_amount' => 100,
            'balance_amount' => 400,
        ], $overrides));

        if ($service) {
            AppointmentLine::create([
                'appointment_id' => $appointment->id,
                'service_id' => $service->id,
                'price_at_booking' => 500,
                'original_service_price' => $service->price,
                'duration_minutes_at_booking' => 30,
                'line_status' => 'booked',
            ]);
        }

        return $appointment->fresh();
    }
}
