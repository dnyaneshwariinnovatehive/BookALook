<?php
require 'vendor/autoload.php';
$app = require_once 'bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

$appointment = \App\Models\Appointment::with('customer', 'salon', 'services', 'serviceAdditions')
    ->whereHas('services', function($q) {
        $q->where('line_status', 'booked');
    })->first();
if (!$appointment) { echo 'No appointment found'; exit; }
$bill = app(\App\Services\AppointmentCheckInService::class)->bill($appointment);
echo 'Bill lines: ' . count($bill['lines']) . PHP_EOL;
$invoice = app(\App\Services\InvoiceService::class)->issueFor($appointment);
echo 'Invoice ID: ' . $invoice?->id . PHP_EOL;
if (!$invoice) { echo 'Failed to issue invoice!'; exit; }
try {
    $url = app(\App\Services\InvoicePdfService::class)->publish($invoice);
    echo 'Published URL: ' . $url . PHP_EOL;
} catch (\Throwable $e) {
    echo 'Error publishing: ' . $e->getMessage() . PHP_EOL;
}
