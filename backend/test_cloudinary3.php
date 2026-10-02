<?php
require 'vendor/autoload.php';
$app = require_once 'bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

$pdfContent = "%PDF-1.4\n%âãÏÓ\n1 0 obj\n<</Type/Catalog/Pages 2 0 R>>\nendobj\n2 0 obj\n<</Type/Pages/Count 1/Kids[3 0 R]>>\nendobj\n3 0 obj\n<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Resources<<>>/Contents 4 0 R>>\nendobj\n4 0 obj\n<</Length 21>>\nstream\nBT /F1 24 Tf 100 100 Td (Hello World)Tj ET\nendstream\nendobj\nxref\n0 5\n0000000000 65535 f \n0000000015 00000 n \n0000000060 00000 n \n0000000111 00000 n \n0000000196 00000 n \ntrailer\n<</Size 5/Root 1 0 R>>\nstartxref\n268\n%%EOF\n";

$stream = fopen('php://temp', 'r+b');
fwrite($stream, $pdfContent);
rewind($stream);
$response = \CloudinaryLabs\CloudinaryLaravel\Facades\Cloudinary::uploadApi()->upload($stream, [
    'public_id' => 'test-valid-pdf',
    'resource_type' => 'image',
]);
echo $response['secure_url'];
