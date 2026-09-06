<?php
use App\Models\User;
use App\Models\Salon;
use Illuminate\Http\Request;
use App\Http\Controllers\Api\Partner\AppointmentController;

$salon = Salon::where('name', 'like', '%salon 2%')->first();
if (!$salon) {
    echo "Salon 2 not found\n";
    exit;
}

$user = User::where('id', $salon->admin_id)->first();
if (!$user) {
    echo "Salon has no admin user\n";
    // fallback
    $user = User::where('role', 'admin')->first();
}

$request = Request::create('/api/partner/salons/' . $salon->id . '/appointments', 'GET');
$request->setUserResolver(function () use ($user) {
    return $user;
});

$controller = app(AppointmentController::class);
try {
    $response = $controller->index($request, $salon->id);
    echo "Status: " . $response->getStatusCode() . "\n";
    echo "Response: " . $response->getContent() . "\n";
} catch (\Exception $e) {
    echo "Exception: " . $e->getMessage() . "\n";
    echo "Trace: " . $e->getTraceAsString() . "\n";
}
