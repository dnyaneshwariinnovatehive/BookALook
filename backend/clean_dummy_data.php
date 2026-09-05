<?php
require __DIR__.'/vendor/autoload.php';
$app = require_once __DIR__.'/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

DB::table('appointments')->delete();
DB::table('appointment_services')->delete();

$salon = App\Models\Salon::where('name', 'salon 2')->first();
$customer = App\Models\User::where('role', 'customer')->first();
$provider = App\Models\ServiceProvider::where('salon_id', $salon->id)->first();
$services = App\Models\Service::where('salon_id', $salon->id)->take(2)->get();

if (!$salon || !$customer || !$provider || $services->isEmpty()) {
    echo "Missing required data to seed appointments.\n";
    exit;
}

$today = Carbon::today()->format('Y-m-d');
$statuses = ['scheduled', 'in_progress', 'completed'];

foreach ($statuses as $index => $status) {
    $appointmentId = (string) Str::uuid();
    $startTime = Carbon::today()->addHours(10 + $index)->format('H:i:s');
    
    DB::table('appointments')->insert([
        'id' => $appointmentId,
        'salon_id' => $salon->id,
        'customer_id' => $customer->id,
        'appointed_provider_id' => $provider->id,
        'serving_provider_id' => $status != 'scheduled' ? $provider->id : null,
        'booking_source' => 'online',
        'appointment_date' => $today,
        'start_time' => $startTime,
        'end_time' => Carbon::today()->addHours(10 + $index)->addMinutes(60)->format('H:i:s'),
        'status' => $status,
        'payment_option' => 'advance_only',
        'total_amount' => 1000,
        'advance_amount' => 200,
        'balance_amount' => 800,
        'qr_token_hash' => hash('sha256', Str::random(32)),
        'created_at' => Carbon::now(),
        'updated_at' => Carbon::now(),
    ]);

    foreach ($services as $service) {
        DB::table('appointment_services')->insert([
            'id' => (string) Str::uuid(),
            'appointment_id' => $appointmentId,
            'service_id' => $service->id,
            'serving_provider_id' => $status != 'scheduled' ? $provider->id : null,
            'price_at_booking' => $service->price,
            'original_service_price' => $service->price,
            'duration_minutes_at_booking' => $service->duration_minutes ?: 30,
            'line_status' => $status,
            'created_at' => Carbon::now(),
            'updated_at' => Carbon::now(),
        ]);
    }
}

echo "Successfully seeded 3 clean appointments for TODAY ($today).\n";
