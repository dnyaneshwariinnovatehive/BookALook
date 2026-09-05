<?php
require __DIR__.'/vendor/autoload.php';
$app = require_once __DIR__.'/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

$saUser = App\Models\User::where('role', 'superadmin')->first();
$token = $saUser->createToken('test')->plainTextToken;

$response = Illuminate\Support\Facades\Http::withToken($token)
    ->get("http://localhost:8000/api/superadmin/appointments");

echo "SA Status: " . $response->status() . "\n";
if ($response->status() != 200) {
    echo "Body: " . $response->body() . "\n";
} else {
    echo "Appointments: " . strlen($response->body()) . "\n";
}
