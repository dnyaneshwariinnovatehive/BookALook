<?php
require 'vendor/autoload.php';
$app = require_once 'bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
try {
    $res = App\Models\Appointment::with([
        'salon:id,name',
        'customer:id,name,phone',
        'appointedProvider:id,user_id,salon_id',
        'servingProvider:id,user_id,salon_id',
        'appointedProvider.user:id,name',
        'servingProvider.user:id,name',
        'services.service',
        'serviceAdditions.service',
        'serviceAdditions.provider.user:id,name'
    ])->paginate(20);
    echo "Success: " . count($res->items()) . " items\n";
} catch (\Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
