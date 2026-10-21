<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\ProviderLeave;
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

class WorkingHoursSyncAndAvailabilityTest extends TestCase
{
    use DatabaseTransactions;

    private User $admin;
    private Salon $salon;
    private User $customer;
    private Service $service;
    private string $unique;

    protected function setUp(): void
    {
        parent::setUp();

        $this->unique = substr(bin2hex(random_bytes(6)), 0, 8);

        // 1. Admin User
        $this->admin = User::create([
            'id' => (string) Str::uuid(),
            'name' => "Admin {$this->unique}",
            'phone' => '91' . substr((string) crc32($this->unique . 'adm'), 0, 8),
            'password_hash' => bcrypt('password'),
            'role' => 'admin',
            'is_active' => true,
        ]);

        // 2. Salon
        $this->salon = Salon::create([
            'id' => (string) Str::uuid(),
            'admin_id' => $this->admin->id,
            'name' => "Salon {$this->unique}",
            'slug' => "salon-{$this->unique}",
            'address' => '123 Market Street',
            'submitted_by' => $this->admin->id,
            'status' => 'active',
        ]);

        // 3. Subscription
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

        // 4. Default Salon Working Hours (09:00 - 18:00, all 7 days open)
        for ($i = 0; $i < 7; $i++) {
            SalonWorkingHour::create([
                'id' => (string) Str::uuid(),
                'salon_id' => $this->salon->id,
                'day_of_week' => $i,
                'is_closed' => false,
                'open_time' => '09:00:00',
                'close_time' => '18:00:00',
            ]);
        }

        // 5. Service Category & Service
        $category = ServiceCategory::first();
        if (! $category) {
            $category = ServiceCategory::create([
                'id' => (string) Str::uuid(),
                'name' => "Hair {$this->unique}",
                'slug' => "hair-{$this->unique}",
                'is_active' => true,
            ]);
        }

        $template = ServiceTemplate::create([
            'id' => (string) Str::uuid(),
            'category_id' => $category->id,
            'name' => "Haircut {$this->unique}",
            'target_gender' => 'unisex',
            'estimated_duration_minutes' => 30,
            'is_active' => true,
        ]);

        $this->service = Service::create([
            'id' => (string) Str::uuid(),
            'salon_id' => $this->salon->id,
            'template_id' => $template->id,
            'price' => 500,
            'advance_amount' => 100,
            'is_active' => true,
        ]);

        // 6. Customer User
        $this->customer = User::create([
            'id' => (string) Str::uuid(),
            'name' => "Customer {$this->unique}",
            'phone' => '91' . substr((string) crc32($this->unique . 'cust'), 0, 8),
            'password_hash' => bcrypt('password'),
            'role' => 'customer',
            'is_active' => true,
        ]);
    }

    private function createStaff(string $name, bool $useSalonHours, ?array $customHours = null): ServiceProvider
    {
        $uniquePhone = '91' . substr((string) crc32($name . $this->unique), 0, 8);
        $user = User::create([
            'id' => (string) Str::uuid(),
            'name' => $name,
            'phone' => $uniquePhone,
            'password_hash' => bcrypt('staff1234'),
            'role' => 'service_provider',
            'is_active' => true,
        ]);

        $provider = ServiceProvider::create([
            'id' => (string) Str::uuid(),
            'user_id' => $user->id,
            'salon_id' => $this->salon->id,
            'specialization' => 'Stylist',
            'base_salary' => 20000,
            'commission_percentage' => 10,
            'auto_approve_leave' => false,
            'use_salon_hours' => $useSalonHours,
            'is_active' => true,
            'joined_at' => now(),
        ]);

        $provider->services()->attach($this->service->id);

        if ($useSalonHours) {
            for ($i = 0; $i < 7; $i++) {
                ProviderWorkingHour::create([
                    'id' => (string) Str::uuid(),
                    'provider_id' => $provider->id,
                    'day_of_week' => $i,
                    'is_weekly_off' => false,
                    'shift_start' => '09:00:00',
                    'shift_end' => '18:00:00',
                    'break_start' => null,
                    'break_end' => null,
                ]);
            }
        } elseif ($customHours) {
            foreach ($customHours as $h) {
                ProviderWorkingHour::create([
                    'id' => (string) Str::uuid(),
                    'provider_id' => $provider->id,
                    'day_of_week' => $h['day_of_week'],
                    'is_weekly_off' => $h['is_weekly_off'],
                    'shift_start' => $h['shift_start'] ?? null,
                    'shift_end' => $h['shift_end'] ?? null,
                    'break_start' => $h['break_start'] ?? null,
                    'break_end' => $h['break_end'] ?? null,
                ]);
            }
        }

        return $provider;
    }

    private function givenCart(): Cart
    {
        Cart::where('customer_id', $this->customer->id)->where('salon_id', $this->salon->id)->delete();
        $cart = Cart::create([
            'id' => (string) Str::uuid(),
            'customer_id' => $this->customer->id,
            'salon_id' => $this->salon->id,
            'status' => 'active',
        ]);
        CartItem::create([
            'id' => (string) Str::uuid(),
            'cart_id' => $cart->id,
            'service_id' => $this->service->id,
            'quantity' => 1,
        ]);
        return $cart;
    }

    public function test_salon_working_hours_update_syncs_to_inherited_providers_only(): void
    {
        // Provider A: inherits salon hours (use_salon_hours = true)
        $staffA = $this->createStaff("Staff A {$this->unique}", true);

        // Provider B: custom schedule (use_salon_hours = false)
        $customHoursB = [];
        for ($i = 0; $i < 7; $i++) {
            $customHoursB[] = [
                'day_of_week' => $i,
                'is_weekly_off' => ($i === 0), // Sunday off
                'shift_start' => ($i === 0) ? null : '11:00:00',
                'shift_end' => ($i === 0) ? null : '16:00:00',
                'break_start' => ($i === 0) ? null : '13:00:00',
                'break_end' => ($i === 0) ? null : '14:00:00',
            ];
        }
        $staffB = $this->createStaff("Staff B {$this->unique}", false, $customHoursB);

        // Admin updates salon working hours to 10:00 - 19:00
        $newSalonHours = [];
        for ($i = 0; $i < 7; $i++) {
            $newSalonHours[] = [
                'day_of_week' => $i,
                'is_closed' => false,
                'open_time' => '10:00:00',
                'close_time' => '19:00:00',
            ];
        }

        $res = $this->actingAs($this->admin, 'sanctum')
            ->putJson("/api/partner/salons/{$this->salon->id}/working-hours", [
                'working_hours' => $newSalonHours,
            ]);

        $res->assertStatus(200);

        // Verify Staff A received updated hours automatically
        $hoursA = ProviderWorkingHour::where('provider_id', $staffA->id)->get();
        $this->assertCount(7, $hoursA);
        foreach ($hoursA as $h) {
            $this->assertFalse((bool) $h->is_weekly_off);
            $this->assertSame('10:00:00', $h->shift_start);
            $this->assertSame('19:00:00', $h->shift_end);
        }

        // Verify Staff B's customized hours and breaks were NOT overwritten
        $hoursB = ProviderWorkingHour::where('provider_id', $staffB->id)->get();
        $this->assertCount(7, $hoursB);
        $sundayB = $hoursB->firstWhere('day_of_week', 0);
        $this->assertTrue((bool) $sundayB->is_weekly_off);
        $mondayB = $hoursB->firstWhere('day_of_week', 1);
        $this->assertFalse((bool) $mondayB->is_weekly_off);
        $this->assertSame('11:00:00', $mondayB->shift_start);
        $this->assertSame('16:00:00', $mondayB->shift_end);
        $this->assertSame('13:00:00', $mondayB->break_start);
        $this->assertSame('14:00:00', $mondayB->break_end);
    }

    public function test_staff_update_can_toggle_between_inherited_and_custom_schedule(): void
    {
        $staff = $this->createStaff("Staff Toggle {$this->unique}", true);

        // Admin updates staff to custom schedule
        $customHours = [];
        for ($i = 0; $i < 7; $i++) {
            $customHours[] = [
                'day_of_week' => $i,
                'is_weekly_off' => false,
                'shift_start' => '12:00:00',
                'shift_end' => '20:00:00',
                'break_start' => '15:00:00',
                'break_end' => '16:00:00',
            ];
        }

        $res = $this->actingAs($this->admin, 'sanctum')
            ->putJson("/api/partner/salons/{$this->salon->id}/staff/{$staff->id}", [
                'use_salon_hours' => false,
                'working_hours' => $customHours,
            ]);

        $res->assertStatus(200);
        $staff->refresh();
        $this->assertFalse((bool) $staff->use_salon_hours);

        $savedHour = ProviderWorkingHour::where('provider_id', $staff->id)->where('day_of_week', 1)->first();
        $this->assertSame('12:00:00', $savedHour->shift_start);
        $this->assertSame('20:00:00', $savedHour->shift_end);
        $this->assertSame('15:00:00', $savedHour->break_start);

        // Now Admin switches staff back to use_salon_hours = true
        $res2 = $this->actingAs($this->admin, 'sanctum')
            ->putJson("/api/partner/salons/{$this->salon->id}/staff/{$staff->id}", [
                'use_salon_hours' => true,
            ]);

        $res2->assertStatus(200);
        $staff->refresh();
        $this->assertTrue((bool) $staff->use_salon_hours);

        // Working hours should immediately reflect current salon hours (09:00 - 18:00)
        $resyncedHour = ProviderWorkingHour::where('provider_id', $staff->id)->where('day_of_week', 1)->first();
        $this->assertSame('09:00:00', $resyncedHour->shift_start);
        $this->assertSame('18:00:00', $resyncedHour->shift_end);
        $this->assertNull($resyncedHour->break_start);
    }

    public function test_provider_profile_endpoint_returns_fresh_working_hours(): void
    {
        $staff = $this->createStaff("Staff Profile {$this->unique}", true);

        $res = $this->actingAs($staff->user, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salon->id}/provider-profile");

        $res->assertStatus(200)
            ->assertJson([
                'success' => true,
                'provider' => [
                    'id' => $staff->id,
                    'use_salon_hours' => true,
                ],
            ]);

        $workingHours = $res->json('provider.working_hours');
        $this->assertCount(7, $workingHours);
        $this->assertSame('09:00:00', $workingHours[0]['shift_start']);
    }

    public function test_customer_provider_listing_excludes_staff_on_approved_full_day_leave(): void
    {
        $this->givenCart();
        $staffAvailable = $this->createStaff("Staff Free {$this->unique}", true);
        $staffOnLeave = $this->createStaff("Staff Leave {$this->unique}", true);

        // Find next open date (tomorrow or +2 days to ensure future date)
        $targetDate = Carbon::tomorrow()->toDateString();

        // Put StaffOnLeave on approved full-day leave on targetDate
        ProviderLeave::create([
            'id' => (string) Str::uuid(),
            'provider_id' => $staffOnLeave->id,
            'leave_date' => $targetDate,
            'leave_type' => 'paid',
            'is_full_day' => true,
            'status' => 'approved',
        ]);

        $res = $this->actingAs($this->customer, 'sanctum')
            ->getJson("/api/customer/salons/{$this->salon->id}/providers?date={$targetDate}");

        $res->assertStatus(200);
        $providers = $res->json('providers');
        $providerIds = collect($providers)->pluck('id')->all();

        $this->assertContains($staffAvailable->id, $providerIds, 'Available staff member should appear in provider list');
        $this->assertNotContains($staffOnLeave->id, $providerIds, 'Staff member on approved full-day leave must be hidden from Customer App');
    }

    public function test_customer_provider_listing_excludes_staff_on_weekly_off(): void
    {
        $this->givenCart();
        $targetDate = Carbon::tomorrow();
        $dayOfWeek = $targetDate->dayOfWeek;

        // Staff Off: has weekly off on this day
        $customHours = [];
        for ($i = 0; $i < 7; $i++) {
            $customHours[] = [
                'day_of_week' => $i,
                'is_weekly_off' => ($i === $dayOfWeek),
                'shift_start' => ($i === $dayOfWeek) ? null : '09:00:00',
                'shift_end' => ($i === $dayOfWeek) ? null : '18:00:00',
            ];
        }
        $staffOff = $this->createStaff("Staff Off {$this->unique}", false, $customHours);
        $staffWorking = $this->createStaff("Staff Working {$this->unique}", true);

        $res = $this->actingAs($this->customer, 'sanctum')
            ->getJson("/api/customer/salons/{$this->salon->id}/providers?date={$targetDate->toDateString()}");

        $res->assertStatus(200);
        $providerIds = collect($res->json('providers'))->pluck('id')->all();

        $this->assertContains($staffWorking->id, $providerIds);
        $this->assertNotContains($staffOff->id, $providerIds, 'Staff with weekly off on the selected date must be hidden');
    }

    public function test_customer_provider_listing_includes_partial_leave_and_slots_exclude_leave_hours(): void
    {
        $this->givenCart();
        $staff = $this->createStaff("Staff Partial {$this->unique}", true);
        $targetDate = Carbon::tomorrow()->toDateString();

        // Approved partial leave between 13:00 and 15:00
        ProviderLeave::create([
            'id' => (string) Str::uuid(),
            'provider_id' => $staff->id,
            'leave_date' => $targetDate,
            'leave_type' => 'unpaid',
            'is_full_day' => false,
            'start_time' => '13:00:00',
            'end_time' => '15:00:00',
            'status' => 'approved',
        ]);

        // 1. Provider listing includes the provider since they have slots outside 13:00-15:00
        $res = $this->actingAs($this->customer, 'sanctum')
            ->getJson("/api/customer/salons/{$this->salon->id}/providers?date={$targetDate}");

        $res->assertStatus(200);
        $providerIds = collect($res->json('providers'))->pluck('id')->all();
        $this->assertContains($staff->id, $providerIds, 'Provider with partial leave must be visible');

        // 2. Slot grid has unavailable slots for 13:00 to 15:00 with reason 'on_leave'
        $slotsRes = $this->actingAs($this->customer, 'sanctum')
            ->getJson("/api/customer/salons/{$this->salon->id}/availability?date={$targetDate}&provider_id={$staff->id}");

        $slotsRes->assertStatus(200);
        $slots = $slotsRes->json('slots');

        $slot10 = collect($slots)->firstWhere('time', '10:00');
        $this->assertTrue($slot10['available'], '10:00 slot should be available');

        $slot13 = collect($slots)->firstWhere('time', '13:00');
        $this->assertFalse($slot13['available'], '13:00 slot should be unavailable during leave');
        $this->assertSame('on_leave', $slot13['reason']);

        $slot14 = collect($slots)->firstWhere('time', '14:00');
        $this->assertFalse($slot14['available'], '14:00 slot should be unavailable during leave');
        $this->assertSame('on_leave', $slot14['reason']);

        $slot16 = collect($slots)->firstWhere('time', '16:00');
        $this->assertTrue($slot16['available'], '16:00 slot should be available after leave ends');
    }

    public function test_booking_validation_revalidates_and_rejects_unavailable_slots(): void
    {
        $this->givenCart();
        $staff = $this->createStaff("Staff Booking {$this->unique}", true);
        $targetDate = Carbon::tomorrow()->toDateString();

        // 1. Partial leave blocks 14:00 - 15:00
        ProviderLeave::create([
            'id' => (string) Str::uuid(),
            'provider_id' => $staff->id,
            'leave_date' => $targetDate,
            'leave_type' => 'unpaid',
            'is_full_day' => false,
            'start_time' => '14:00:00',
            'end_time' => '15:00:00',
            'status' => 'approved',
        ]);

        // Attempt booking at 14:00 during leave -> should be rejected with 409
        $conflictRes = $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/appointments/book", [
                'date' => $targetDate,
                'time' => '14:00',
                'provider_id' => $staff->id,
            ]);

        $conflictRes->assertStatus(409);
        $this->assertTrue($conflictRes->json('slot_unavailable'));

        // Attempt booking at 10:00 -> should succeed
        $successRes = $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/appointments/book", [
                'date' => $targetDate,
                'time' => '10:00',
                'provider_id' => $staff->id,
            ]);

        $successRes->assertStatus(201);
        $appointmentId = $successRes->json('appointment.id');
        $this->assertNotNull($appointmentId);

        // Another customer attempts booking at 10:00 -> should be rejected with 409 because slot is held
        $customer2 = User::create([
            'id' => (string) Str::uuid(),
            'name' => "Customer2 {$this->unique}",
            'phone' => '91' . substr((string) crc32($this->unique . 'c2'), 0, 8),
            'password_hash' => bcrypt('password'),
            'role' => 'customer',
            'is_active' => true,
        ]);
        $cart2 = Cart::create([
            'id' => (string) Str::uuid(),
            'customer_id' => $customer2->id,
            'salon_id' => $this->salon->id,
            'status' => 'active',
        ]);
        CartItem::create([
            'id' => (string) Str::uuid(),
            'cart_id' => $cart2->id,
            'service_id' => $this->service->id,
            'quantity' => 1,
        ]);

        $doubleBookRes = $this->actingAs($customer2, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/appointments/book", [
                'date' => $targetDate,
                'time' => '10:00',
                'provider_id' => $staff->id,
            ]);

        $doubleBookRes->assertStatus(409);
        $this->assertTrue($doubleBookRes->json('slot_unavailable'));
    }
}
