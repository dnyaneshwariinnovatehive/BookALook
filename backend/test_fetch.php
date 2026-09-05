<?php
require __DIR__.'/vendor/autoload.php';
$app = require_once __DIR__.'/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

$salon = App\Models\Salon::find('a2a7bd03-2393-48f4-bf8c-f1e55079bfee');
$appointments = App\Models\Appointment::with(['customer', 'services.service', 'serviceAdditions.service'])->where('salon_id', $salon->id)->get();
echo "Count: " . $appointments->count() . "\n";
try {
    $json = json_encode(['appointments' => $appointments], JSON_THROW_ON_ERROR);
    echo "JSON OK. Length: " . strlen($json) . "\n";
} catch (\Exception $e) {
    echo "JSON Error: " . $e->getMessage() . "\n";
}
