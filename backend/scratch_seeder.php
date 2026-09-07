<?php
require 'vendor/autoload.php';
$app = require_once 'bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Models\User;
use App\Models\Salon;
use App\Models\Combo;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceTemplate;
use App\Models\SalonWallet;
use App\Models\WalletTransaction;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPlan;
use App\Models\Appointment;
use App\Models\AppointmentService;
use App\Models\AppointmentServiceAddition;
use App\Models\SalonPayout;
use App\Models\SalaryPayout;
use App\Models\ServiceProvider;
use App\Models\Notification;
use Carbon\Carbon;
use Illuminate\Support\Str;
use Illuminate\Support\Facades\DB;

try {
    DB::beginTransaction();

    $phones = ['9112002049', '9168281183'];
    $users = User::whereIn('phone', $phones)->get();
    $salons = Salon::whereIn('admin_id', $users->pluck('id'))->get();

    if ($salons->count() < 2) {
        throw new Exception("Could not find both salons. Found: " . $salons->count());
    }

    $salon1 = $salons->first();
    $salon2 = $salons->last();

    $customer = User::where('role', 'customer')->first();
    if (!$customer) {
        $customer = User::create([
            'id' => Str::uuid(),
            'name' => 'Test Customer',
            'phone' => '1234567890',
            'role' => 'customer',
            'is_active' => true,
            'password_hash' => bcrypt('password')
        ]);
    }

    $category = ServiceCategory::firstOrCreate(
        ['name' => 'Test Category'],
        ['id' => Str::uuid(), 'is_active' => true]
    );

    $template1 = ServiceTemplate::firstOrCreate(
        ['name' => 'Haircut Test', 'category_id' => $category->id],
        ['id' => Str::uuid(), 'estimated_duration_minutes' => 30, 'is_active' => true]
    );

    $template2 = ServiceTemplate::firstOrCreate(
        ['name' => 'Spa Test', 'category_id' => $category->id],
        ['id' => Str::uuid(), 'estimated_duration_minutes' => 60, 'is_active' => true]
    );

    $plan = SubscriptionPlan::first();
    if (!$plan) {
        $plan = SubscriptionPlan::create([
            'id' => Str::uuid(),
            'name' => 'Test Plan',
            'price' => 1000,
            'is_active' => true
        ]);
    }

    foreach ([$salon1, $salon2] as $index => $salon) {
        echo "Processing Salon: {$salon->name}\n";

        // Provider
        $provider = ServiceProvider::where('salon_id', $salon->id)->first();
        if (!$provider) {
            $userProv = User::create([
                'id' => Str::uuid(),
                'name' => 'Provider for ' . $salon->name,
                'phone' => '999999' . rand(1000, 9999),
                'role' => 'service_provider',
                'password_hash' => bcrypt('password')
            ]);
            $provider = ServiceProvider::create([
                'id' => Str::uuid(),
                'salon_id' => $salon->id,
                'user_id' => $userProv->id,
                'base_salary' => 1000,
                'commission_percentage' => 10,
                'is_active' => true
            ]);
        }

        // Services
        $service1 = Service::firstOrCreate(
            ['salon_id' => $salon->id, 'template_id' => $template1->id],
            ['id' => Str::uuid(), 'price' => 500, 'is_active' => true]
        );
        
        $service2 = Service::firstOrCreate(
            ['salon_id' => $salon->id, 'template_id' => $template2->id],
            ['id' => Str::uuid(), 'price' => 1000, 'is_active' => true]
        );

        // 6. Combo + Services
        $combo = Combo::firstOrCreate(
            ['salon_id' => $salon->id, 'name' => 'Special Combo'],
            ['id' => Str::uuid(), 'advance_percentage' => 25, 'is_active' => true]
        );
        
        DB::table('combo_services')->updateOrInsert(
            ['combo_id' => $combo->id, 'service_id' => $service1->id],
            ['combo_special_price' => 400]
        );
        DB::table('combo_services')->updateOrInsert(
            ['combo_id' => $combo->id, 'service_id' => $service2->id],
            ['combo_special_price' => 800]
        );

        // 1. Dynamic Bill
        $appt = Appointment::create([
            'id' => Str::uuid(),
            'salon_id' => $salon->id,
            'customer_id' => $customer->id,
            'appointed_provider_id' => $provider->id,
            'serving_provider_id' => $provider->id,
            'booking_source' => 'online',
            'appointment_date' => Carbon::today()->format('Y-m-d'),
            'start_time' => '10:00:00',
            'end_time' => '10:30:00',
            'status' => 'completed',
            'payment_option' => 'advance_only',
            'total_amount' => 550, // 500 + 50
            'final_billed_amount' => 550,
            'qr_token_hash' => 'hash123',
        ]);

        AppointmentService::create([
            'id' => Str::uuid(),
            'appointment_id' => $appt->id,
            'service_id' => $service1->id,
            'price_at_booking' => 500,
            'original_service_price' => 500,
            'duration_minutes_at_booking' => 30,
            'line_status' => 'completed'
        ]);

        AppointmentServiceAddition::create([
            'id' => Str::uuid(),
            'appointment_id' => $appt->id,
            'service_id' => $service2->id,
            'provider_id' => $provider->id,
            'added_by' => $provider->user_id,
            'price_at_addition' => 50,
            'duration_minutes_at_addition' => 10,
            'status' => 'active'
        ]);

        // 2. Wallet & Coin Reward
        $wallet = SalonWallet::firstOrCreate(['salon_id' => $salon->id], ['coin_balance' => 0]);
        $wallet->coin_balance += 500;
        $wallet->save();

        WalletTransaction::create([
            'id' => Str::uuid(),
            'salon_id' => $salon->id,
            'type' => 'earned',
            'coins' => 500,
            'balance_after' => $wallet->coin_balance,
            'note' => 'Reward for milestone'
        ]);

        // 3 & 4. Payout System & Distribution
        SalonPayout::create([
            'id' => Str::uuid(),
            'salon_id' => $salon->id,
            'cycle_week_start_date' => Carbon::now()->subDays(7),
            'cycle_week_end_date' => Carbon::now(),
            'gross_amount' => 550,
            'commission_deducted' => 55,
            'net_amount' => 495,
            'status' => 'pending'
        ]);

        SalaryPayout::create([
            'id' => Str::uuid(),
            'provider_id' => $provider->id,
            'salon_id' => $salon->id,
            'salary_month' => Carbon::now()->startOfMonth(),
            'base_salary_snapshot' => 1000,
            'commission_earned' => 55,
            'total_payable' => 1055,
            'status' => 'pending'
        ]);

        // 5. Subscription Plan End & Notification
        SalonSubscription::where('salon_id', $salon->id)->delete();
        if ($index == 0) {
            // Salon 1 is Active
            SalonSubscription::create([
                'id' => Str::uuid(),
                'salon_id' => $salon->id,
                'plan_id' => $plan->id,
                'billing_type' => 'flat',
                'plan_price_snapshot' => 1000,
                'start_date' => Carbon::now()->subDays(10),
                'end_date' => Carbon::now()->addDays(20),
                'status' => 'active'
            ]);
        } else {
            // Salon 2 is Expired
            SalonSubscription::create([
                'id' => Str::uuid(),
                'salon_id' => $salon->id,
                'plan_id' => $plan->id,
                'billing_type' => 'flat',
                'plan_price_snapshot' => 1000,
                'start_date' => Carbon::now()->subDays(40),
                'end_date' => Carbon::now()->subDays(10), // Expired 10 days ago
                'status' => 'expired'
            ]);
            
            // Notification for subscription expiry
            Notification::create([
                'id' => Str::uuid(),
                'user_id' => $salon->admin_id,
                'type' => 'subscription_expiring',
                'title' => 'Subscription Expired',
                'message' => 'Your subscription has ended. Customer bookings are disabled.'
            ]);
        }
    }

    DB::commit();
    echo "Test data successfully seeded!\n";
} catch (\Exception $e) {
    DB::rollBack();
    echo "Failed to seed data: " . $e->getMessage() . "\n" . $e->getTraceAsString();
}
