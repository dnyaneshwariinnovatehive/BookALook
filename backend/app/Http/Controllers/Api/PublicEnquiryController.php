<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\City;
use App\Models\SalonEnquiry;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;

class PublicEnquiryController extends Controller
{
    public function store(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'salon_name' => 'required|string|max:150',
            'owner_name' => 'required|string|max:150',
            'phone' => 'required|string|max:15',
            // Picked from a dropdown now, not typed. The old free-text city is
            // what left this table holding "navi mumbai" and "Pimpri
            // Chinchwad" — unmatchable against anything, which is exactly what
            // assigning a nearby collaborator needs to do.
            'city_id' => 'required|uuid|exists:cities,id',
            'sub_area_id' => [
                'required', 'uuid',
                Rule::exists('sub_areas', 'id')->where(
                    fn ($q) => $q->where('city_id', $request->city_id)
                ),
            ],
            'street_address' => 'required|string|max:255',
            'pincode' => 'required|string|max:20',
            'message' => 'nullable|string',
        ], [
            'city_id.required' => 'Please choose your city.',
            'sub_area_id.required' => 'Please choose your area.',
            'sub_area_id.exists' => 'That area is not in the city you picked.',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        try {
            $city = City::find($request->city_id);

            $enquiry = SalonEnquiry::create([
                'salon_name' => $request->salon_name,
                'owner_name' => $request->owner_name,
                'phone' => $request->phone,
                'city_id' => $request->city_id,
                'sub_area_id' => $request->sub_area_id,
                'street_address' => $request->street_address,
                'pincode' => $request->pincode,
                // The readable name is still stored, so the older rows and the
                // new ones read the same way anywhere that only wants a label.
                'city' => $city?->name,
                'message' => $request->message,
                'status' => 'new',
            ]);

            return response()->json([
                'message' => 'Enquiry submitted successfully.',
                'enquiry' => $enquiry
            ], 201);
        } catch (\Exception $e) {
            return response()->json([
                'message' => 'Failed to submit enquiry',
                'error' => $e->getMessage()
            ], 500);
        }
    }
}
