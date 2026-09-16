<?php

$user = \App\Models\User::where('phone', '9112002049')->first();
if (!$user) {
    echo "User not found with phone 9112002049\n";
    exit;
}

echo "User ID: {$user->id}, Name: {$user->name}, Role: {$user->role}\n";

$salon = \App\Models\Salon::where('vendor_id', $user->id)->first();
if (!$salon) {
    echo "Salon not found for this vendor\n";
    // Check if user belongs to a salon (staff)
    if (isset($user->salon_id)) {
        $salon = \App\Models\Salon::find($user->salon_id);
    }
}

if ($salon) {
    echo "Salon ID: {$salon->id}, Name: {$salon->name}\n";
} else {
    echo "No salon associated with this user.\n";
}

$services = \App\Models\Service::where('salon_id', $salon->id ?? 0)->get();
echo "Services count: {$services->count()}\n";
if ($services->count() > 0) {
    echo "Sample Service ID: {$services->first()->id}, Name: {$services->first()->name}\n";
}

$customers = \App\Models\User::where('role', 'customer')->take(5)->get();
echo "Customers count: {$customers->count()}\n";
if ($customers->count() > 0) {
    echo "Sample Customer ID: {$customers->first()->id}\n";
}
