<?php
require __DIR__ . '/vendor/autoload.php';
$app = require_once __DIR__.'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\Storage;
use Illuminate\Http\File;

try {
    $file = new File(__DIR__ . '/public/favicon.ico');
    $path = Storage::disk('cloudinary')->putFile('test', $file);
    $url = Storage::disk('cloudinary')->url($path);
    echo "Success: " . $url . "\n";
} catch (\Exception $e) {
    echo "Exception: " . $e->getMessage() . "\n";
    echo $e->getTraceAsString() . "\n";
} catch (\Error $e) {
    echo "Error: " . $e->getMessage() . "\n";
    echo $e->getTraceAsString() . "\n";
}
