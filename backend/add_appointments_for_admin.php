<?php
use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Models\User;
use App\Models\Appointment;
use App\Models\Service;
use App\Models\ServiceTemplate;
use App\Models\ServiceCategory;
use Illuminate\Support\Str;
use Carbon\Carbon;

$admin = User::where('phone', '9112002049')->first();
if (!$admin) {
    echo "Admin user not found.\n";
    exit;
}

$salon = Salon::where('admin_id', $admin->id)->first();
if (!$salon) {
    echo "Salon not found, creating one...\n";
    $salon = Salon::create([
        'admin_id' => $admin->id,
        'name' => 'Premium Salon',
        'slug' => 'premium-salon-' . Str::random(5),
        'city' => 'Mumbai',
        'address' => '123 Main St, Mumbai',
        'status' => 'approved',
        'submitted_by' => $admin->id,
        'approved_by' => $admin->id,
        'approved_at' => now(),
    ]);
}

$category = ServiceCategory::first();
if (!$category) {
    $category = ServiceCategory::create(['name' => 'Hair Care', 'is_active' => true, 'id' => Str::uuid()]);
}

$template = ServiceTemplate::first();
if (!$template) {
    $template = ServiceTemplate::create([
        'category_id' => $category->id,
        'name' => 'Haircut',
        'estimated_duration_minutes' => 30,
        'is_active' => true
    ]);
}

$service = Service::where('salon_id', $salon->id)->first();
if (!$service) {
    $service = Service::create([
        'salon_id' => $salon->id,
        'template_id' => $template->id,
        'description' => 'A premium haircut',
        'price' => 250.00,
        'is_active' => true,
    ]);
}

$provider = ServiceProvider::where('salon_id', $salon->id)->first();
if (!$provider) {
    // create dummy user for provider
    $providerUser = User::create([
        'name' => 'Expert Stylist',
        'email' => 'stylist@premium.com',
        'password' => bcrypt('password'),
        'role' => 'staff',
        'phone' => '9876543210'
    ]);
    $provider = ServiceProvider::create([
        'user_id' => $providerUser->id,
        'salon_id' => $salon->id,
        'specialization' => 'Hair Expert',
        'is_active' => true,
    ]);
}

$customer = User::where('role', 'customer')->first();
if (!$customer) {
    $customer = User::create([
        'name' => 'Loyal Customer',
        'email' => 'customer@salon.com',
        'password' => bcrypt('password'),
        'role' => 'customer',
        'phone' => '8888888888'
    ]);
}

// Ensure at least some appointments for today and tomorrow
$appointmentsToCreate = [
    // Today
    ['date' => Carbon::today(), 'time' => '10:00:00', 'status' => 'scheduled'],
    ['date' => Carbon::today(), 'time' => '12:00:00', 'status' => 'in_progress'],
    ['date' => Carbon::today(), 'time' => '15:00:00', 'status' => 'completed'],
    ['date' => Carbon::today(), 'time' => '17:00:00', 'status' => 'scheduled'],
    
    // Tomorrow
    ['date' => Carbon::tomorrow(), 'time' => '09:00:00', 'status' => 'scheduled'],
    ['date' => Carbon::tomorrow(), 'time' => '11:00:00', 'status' => 'scheduled'],
    ['date' => Carbon::tomorrow(), 'time' => '14:00:00', 'status' => 'scheduled'],
    ['date' => Carbon::tomorrow(), 'time' => '16:00:00', 'status' => 'scheduled'],
];

foreach ($appointmentsToCreate as $aptData) {
    $startTime = Carbon::parse($aptData['date']->format('Y-m-d') . ' ' . $aptData['time']);
    $endTime = (clone $startTime)->addMinutes($template->estimated_duration_minutes);

    $appointment = Appointment::create([
        'salon_id' => $salon->id,
        'customer_id' => $customer->id,
        'appointed_provider_id' => $provider->id,
        'serving_provider_id' => $aptData['status'] != 'scheduled' ? $provider->id : null,
        'booking_source' => 'online',
        'appointment_date' => $startTime->format('Y-m-d'),
        'start_time' => $startTime->format('H:i:s'),
        'end_time' => $endTime->format('H:i:s'),
        'status' => $aptData['status'],
        'payment_option' => 'advance_only',
        'total_amount' => $service->price,
        'advance_amount' => $service->price * 0.2,
        'balance_amount' => $service->price * 0.8,
        'qr_token_hash' => hash('sha256', Str::random(10)),
        'started_at' => $aptData['status'] == 'in_progress' ? $startTime : null,
        'completed_at' => $aptData['status'] == 'completed' ? $endTime : null,
    ]);

    \Illuminate\Support\Facades\DB::table('appointment_services')->insert([
        'id' => (string) Str::uuid(),
        'appointment_id' => $appointment->id,
        'service_id' => $service->id,
        'serving_provider_id' => $aptData['status'] != 'scheduled' ? $provider->id : null,
        'price_at_booking' => $service->price,
        'original_service_price' => $service->price,
        'duration_minutes_at_booking' => $template->estimated_duration_minutes,
        'line_status' => $aptData['status'],
        'created_at' => now(),
        'updated_at' => now(),
    ]);
}

echo "Appointments created successfully for Salon ID: {$salon->id}\n";
