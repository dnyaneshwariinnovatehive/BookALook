<?php
$user = \App\Models\User::where('phone', '9112002049')->first();
$token = $user->createToken('test')->plainTextToken;

echo "TOKEN: " . $token . "\n";

$plansResp = file_get_contents("http://127.0.0.1:8000/api/partner/subscription/plans", false, stream_context_create([
    'http' => [
        'header' => "Authorization: Bearer " . $token . "\r\nAccept: application/json\r\n"
    ]
]));

echo "PLANS: " . $plansResp . "\n";

$walletResp = file_get_contents("http://127.0.0.1:8000/api/partner/wallet", false, stream_context_create([
    'http' => [
        'header' => "Authorization: Bearer " . $token . "\r\nAccept: application/json\r\n"
    ]
]));

echo "WALLET: " . $walletResp . "\n";
