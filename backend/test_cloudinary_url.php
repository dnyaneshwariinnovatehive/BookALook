<?php
require 'vendor/autoload.php';
$app = require_once 'bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

$pdf = app('dompdf.wrapper')->loadHTML('<h1>Test PDF</h1>')->output();

$stream = fopen('php://temp', 'r+b');
fwrite($stream, $pdf);
rewind($stream);
$response = \CloudinaryLabs\CloudinaryLaravel\Facades\Cloudinary::uploadApi()->upload($stream, [
    'public_id' => 'test-raw-dompdf',
    'resource_type' => 'raw',
    'filename' => 'test.pdf'
]);
$url = $response['secure_url'];
echo "Unsigned: " . $url . PHP_EOL;

// Generate signed URL
$signedUrl = cloudinary_url('test-raw-dompdf.pdf', [
    'resource_type' => 'raw',
    'sign_url' => true,
]);
echo "Signed: " . $signedUrl . PHP_EOL;
