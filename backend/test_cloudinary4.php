<?php
require 'vendor/autoload.php';
$app = require_once 'bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

$pdf = app('dompdf.wrapper')->loadHTML('<h1>Test PDF</h1>')->output();

// Option 1: temp file
$tmp = tempnam(sys_get_temp_dir(), 'pdf');
file_put_contents($tmp, $pdf);

try {
    $response = \CloudinaryLabs\CloudinaryLaravel\Facades\Cloudinary::uploadApi()->upload($tmp, [
        'public_id' => 'test-valid-dompdf',
        'resource_type' => 'image',
    ]);
    echo "Image resource: " . $response['secure_url'] . PHP_EOL;
} catch (\Throwable $e) {
    echo "Image resource error: " . $e->getMessage() . PHP_EOL;
}
unlink($tmp);
