<?php

use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Models\User;
use App\Models\Appointment;
use App\Models\Service;
use App\Models\AppointmentService;
use Carbon\Carbon;

// Ensure we are in a Laravel environment
require __DIR__.'/vendor/autoload.php';
$app = require_once __DIR__.'/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

$provider = ServiceProvider::first();
if (!$provider) {
    echo "No providers found in DB.\n";
    exit;
}

$salon = Salon::find($provider->salon_id);
if (!$salon) {
    echo "Salon for provider not found.\n";
    exit;
}

$customer = User::where('role', 'customer')->first();
if (!$customer) {
    $customer = User::create([
        'name' => 'Dummy Customer',
        'email' => 'dummy@customer.com',
        'password' => bcrypt('password'),
        'role' => 'customer',
        'phone' => '1234567890'
    ]);
}

$services = Service::where('salon_id', $salon->id)->take(2)->get();
if ($services->isEmpty()) {
    $service = Service::create([
        'salon_id' => $salon->id,
        'category_id' => null,
        'name' => 'Dummy Haircut',
        'description' => 'A great haircut',
        'price' => 50.00,
        'duration_minutes' => 30,
        'is_active' => true,
    ]);
    $services = collect([$service]);
}

$appointmentsToCreate = [
    // Today
    ['date' => Carbon::today(), 'time' => '10:00:00', 'status' => 'scheduled'],
    ['date' => Carbon::today(), 'time' => '11:00:00', 'status' => 'in_progress'],
    ['date' => Carbon::today(), 'time' => '14:00:00', 'status' => 'completed'],
    
    // Tomorrow
    ['date' => Carbon::tomorrow(), 'time' => '09:00:00', 'status' => 'scheduled'],
    ['date' => Carbon::tomorrow(), 'time' => '13:00:00', 'status' => 'scheduled'],
    
    // Yesterday
    ['date' => Carbon::yesterday(), 'time' => '15:00:00', 'status' => 'completed'],
    ['date' => Carbon::yesterday(), 'time' => '16:00:00', 'status' => 'no_show'],
];

foreach ($appointmentsToCreate as $aptData) {
    $totalAmount = $services->sum('price');
    $totalDuration = $services->map(function($s) { return $s->duration_minutes ?: 30; })->sum();
    $startTime = Carbon::parse($aptData['date']->format('Y-m-d') . ' ' . $aptData['time']);
    $endTime = (clone $startTime)->addMinutes($totalDuration);

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
        'total_amount' => $totalAmount,
        'advance_amount' => $totalAmount * 0.2, // 20% advance
        'balance_amount' => $totalAmount * 0.8,
        'qr_token_hash' => hash('sha256', \Illuminate\Support\Str::random(10)),
        'started_at' => $aptData['status'] == 'in_progress' ? $startTime : null,
        'completed_at' => $aptData['status'] == 'completed' ? $endTime : null,
    ]);

    foreach ($services as $service) {
        \Illuminate\Support\Facades\DB::table('appointment_services')->insert([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'appointment_id' => $appointment->id,
            'service_id' => $service->id,
            'serving_provider_id' => $aptData['status'] != 'scheduled' ? $provider->id : null,
            'price_at_booking' => $service->price,
            'original_service_price' => $service->price,
            'duration_minutes_at_booking' => $service->duration_minutes ?: 30,
            'line_status' => $aptData['status']
        ]);
    }
}

echo "Created " . count($appointmentsToCreate) . " dummy appointments for provider ID {$provider->id} at salon ID {$salon->id}.\n";
