<?php
require __DIR__.'/vendor/autoload.php';
$app = require_once __DIR__.'/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

echo "--- Users ---\n";
foreach (App\Models\User::all() as $u) {
    echo "User: {$u->id} | {$u->email} | {$u->role}\n";
}

echo "\n--- Salons ---\n";
foreach (App\Models\Salon::all() as $s) {
    echo "Salon: {$s->id} | {$s->name} | Owner: {$s->owner_id}\n";
}

echo "\n--- Providers ---\n";
foreach (App\Models\ServiceProvider::all() as $p) {
    echo "Provider: {$p->id} | User: {$p->user_id} | Salon: {$p->salon_id}\n";
}

echo "\n--- Appointments ---\n";
foreach (App\Models\Appointment::all() as $a) {
    echo "Apt: {$a->id} | Salon: {$a->salon_id} | Provider: {$a->appointed_provider_id}\n";
}
