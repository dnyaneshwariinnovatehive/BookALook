<?php
$request = \Illuminate\Http\Request::create('/api/enquiries', 'POST', [
    'salon_name' => 'Test Salon',
    'owner_name' => 'Test Owner',
    'phone' => '9999999999',
    'city_id' => App\Models\City::first()->id,
    'sub_area_id' => App\Models\SubArea::where('city_id', App\Models\City::first()->id)->first()->id,
    'street_address' => '123 Test St',
    'pincode' => '400001',
    'message' => 'Hello',
]);
$controller = new \App\Http\Controllers\Api\PublicEnquiryController();
$response = $controller->store($request);
echo $response->getContent();
