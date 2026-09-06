<?php
use App\Models\User;
use App\Models\Salon;

$salon = Salon::where('name', 'like', '%salon 2%')->first();
$admin = User::where('id', $salon->admin_id)->first();
if (!$admin) {
    $admin = User::where('role', 'admin')->first();
}

// Generate token manually
$token = $admin->createToken('test-token')->plainTextToken;

// Fetch appointments
$ch2 = curl_init('http://localhost:8000/api/partner/salons/' . $salon->id . '/appointments');
curl_setopt($ch2, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch2, CURLOPT_HTTPHEADER, [
    'Authorization: Bearer ' . $token,
    'Accept: application/json'
]);
$response2 = curl_exec($ch2);
$httpcode2 = curl_getinfo($ch2, CURLINFO_HTTP_CODE);
curl_close($ch2);

echo "Appointments Status: $httpcode2\n";
echo "Appointments Response: " . substr($response2, 0, 500) . "\n";
