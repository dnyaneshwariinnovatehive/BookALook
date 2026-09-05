<?php
require __DIR__.'/vendor/autoload.php';
$app = require_once __DIR__.'/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

\Illuminate\Support\Facades\Schema::table('subscription_payment_requests', function ($table) {
    $table->uuid('salon_id')->change();
});

echo "Migration done\n";
