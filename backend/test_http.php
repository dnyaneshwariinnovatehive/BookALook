<?php
require __DIR__.'/vendor/autoload.php';
$app = require_once __DIR__.'/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

use Illuminate\Http\Request;

// 1. Get Service Provider token
$providerUser = App\Models\User::where('role', 'service_provider')->first();
$token = $providerUser->createToken('test')->plainTextToken;
$provider = App\Models\ServiceProvider::where('user_id', $providerUser->id)->first();
$salonId = $provider->salon_id;

echo "Provider Token: $token\n";
echo "Salon ID: $salonId\n";

// Use built-in HTTP client to simulate request
$appointment = App\Models\Appointment::with(['customer', 'services.service', 'serviceAdditions.service'])->where('salon_id', $salonId)->first();
echo json_encode($appointment, JSON_PRETTY_PRINT) . "\n";

// 2. Get Admin token
$adminUser = App\Models\User::where('role', 'admin')->first();
$adminToken = $adminUser->createToken('test')->plainTextToken;

$response = Illuminate\Support\Facades\Http::withToken($adminToken)
    ->get("http://localhost:8000/api/partner/salons/{$salonId}/appointments?date=".date('Y-m-d'));

echo "Admin Status: " . $response->status() . "\n";
echo "Admin Body: " . substr($response->body(), 0, 500) . "\n";
