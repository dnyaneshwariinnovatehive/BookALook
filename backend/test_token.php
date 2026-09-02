<?php
require __DIR__.'/vendor/autoload.php';
$app = require_once __DIR__.'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$user = App\Models\User::where('role', 'superadmin')->first();
if (!$user) {
    echo "No superadmin user found\n";
    exit;
}
$token = $user->createToken('test')->plainTextToken;
echo "Token: $token\n";

$ch = curl_init('http://localhost:8000/api/superadmin/banners');
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'Accept: application/json',
    'Authorization: Bearer ' . $token
]);
$response = curl_exec($ch);
$status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
echo "Status: $status\n";
echo "Response: $response\n";
