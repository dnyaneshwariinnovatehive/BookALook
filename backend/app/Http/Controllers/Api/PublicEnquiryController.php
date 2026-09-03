<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\SalonEnquiry;
use Illuminate\Support\Facades\Validator;

class PublicEnquiryController extends Controller
{
    public function store(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'salon_name' => 'required|string|max:150',
            'owner_name' => 'required|string|max:150',
            'phone' => 'required|string|max:15',
            'city' => 'nullable|string|max:100',
            'message' => 'nullable|string',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        try {
            $enquiry = SalonEnquiry::create([
                'salon_name' => $request->salon_name,
                'owner_name' => $request->owner_name,
                'phone' => $request->phone,
                'city' => $request->city,
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
