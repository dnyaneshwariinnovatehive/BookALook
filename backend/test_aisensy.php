<?php

require __DIR__.'/vendor/autoload.php';
$app = require_once __DIR__.'/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

$message = \App\Models\WhatsAppMessage::create([
    'to_phone' => '+919999999999',
    'template' => 'test_whatsapp_appointment_reminder',
    'campaign' => 'BAL_apt_reminder',
    'payload' => ['parameters' => ['Glow Studio', 'October 7, 2026 at 4:30 PM', '123 MG Road, Pune']],
    'status' => 'queued',
    'category' => 'test',
]);
\App\Jobs\SendWhatsAppMessageJob::dispatchSync($message->id);
$message->refresh();
echo json_encode($message->toArray(), JSON_PRETTY_PRINT);
