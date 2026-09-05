<?php
require __DIR__.'/vendor/autoload.php';
$app = require_once __DIR__.'/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

$count = \Illuminate\Support\Facades\DB::table('appointment_services')->count();
echo "Total services in DB: $count\n";

$services = \Illuminate\Support\Facades\DB::table('appointment_services')->get();
foreach ($services as $s) {
    echo "Service ID: {$s->id} | Appointment ID: {$s->appointment_id}\n";
}
