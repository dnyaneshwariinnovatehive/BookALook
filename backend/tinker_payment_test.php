<?php
$user = \App\Models\User::where('phone', '9112002049')->first();
$token = $user->createToken('test')->plainTextToken;

echo "TOKEN: " . $token . "\n";

// We need an image to upload. Let's create a dummy image
$imagePath = __DIR__ . '/dummy.png';
$image = imagecreate(100, 100);
imagecolorallocate($image, 255, 0, 0);
imagepng($image, $imagePath);
imagedestroy($image);

$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, "http://127.0.0.1:8000/api/partner/subscription/payment-request");
curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
curl_setopt($ch, CURLOPT_POST, 1);

$post = [
    'plan_id' => \App\Models\SubscriptionPlan::first()->id,
    'billing_type' => 'flat',
    'screenshot' => new \CURLFile($imagePath, 'image/png', 'dummy.png')
];
curl_setopt($ch, CURLOPT_POSTFIELDS, $post);

curl_setopt($ch, CURLOPT_HTTPHEADER, [
    "Authorization: Bearer " . $token,
    "Accept: application/json"
]);

$result = curl_exec($ch);
if (curl_errno($ch)) {
    echo 'Error:' . curl_error($ch);
}
curl_close($ch);

echo "RESULT: " . $result . "\n";
@unlink($imagePath);
