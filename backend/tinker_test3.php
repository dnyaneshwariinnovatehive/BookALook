<?php
use App\Models\User;
use App\Models\Salon;
use Illuminate\Http\Request;
use App\Http\Controllers\Api\Partner\PartnerSubscriptionController;

$user = User::where('phone', '9112002049')->first();
$request = Request::create('/partner/subscription', 'GET');
$request->setUserResolver(function () use ($user) {
    return $user;
});

$controller = new PartnerSubscriptionController();
$response = $controller->getSubscription($request);
echo "Subscription Response:\n";
echo $response->getContent();

echo "\n\nPlans Response:\n";
$plansResponse = $controller->getPlans();
echo $plansResponse->getContent();
