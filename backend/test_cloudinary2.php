<?php
require 'vendor/autoload.php';
$app = require_once 'bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

$stream = fopen('php://temp', 'r+b');
fwrite($stream, 'Dummy PDF content');
rewind($stream);
$response = \CloudinaryLabs\CloudinaryLaravel\Facades\Cloudinary::uploadApi()->upload($stream, [
    'public_id' => 'test-invoice-image',
    'resource_type' => 'image',
    'format' => 'pdf',
]);
echo $response['secure_url'];
