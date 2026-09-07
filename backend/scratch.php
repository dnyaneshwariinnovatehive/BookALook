<?php
require 'vendor/autoload.php';
$app = require_once 'bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$users = App\Models\User::whereIn('phone', ['9112002049', '9168281183'])->get();
echo "USERS:\n" . json_encode($users, JSON_PRETTY_PRINT) . "\n";
$salons = App\Models\Salon::whereIn('admin_id', $users->pluck('id'))->get();
echo "SALONS:\n" . json_encode($salons, JSON_PRETTY_PRINT) . "\n";
