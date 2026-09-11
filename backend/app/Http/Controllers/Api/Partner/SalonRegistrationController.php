<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\User;
use App\Models\Salon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class SalonRegistrationController extends Controller
{
    public function register(Request $request)
    {
        $request->validate([
            // Owner Account Details
            'full_name' => 'required|string|max:150',
            'email' => 'required|email|max:150|unique:users,email',
            'phone_number' => 'required|string|max:15|unique:users,phone',
            'password' => 'required|string|min:6',
            
            // Salon Details
            'salon_name' => 'required|string|max:150',
            'description' => 'nullable|string',
            'street_address' => 'required|string',
            'city_id' => 'required|exists:cities,id',
            'pincode' => 'required|string|max:10',
            // Optional: an owner registering from a laptop at home should not
            // be blocked, and they can drop the pin later from the app.
            'latitude' => 'nullable|numeric|between:-90,90',
            'longitude' => 'nullable|numeric|between:-180,180',
            'gender_focus' => 'nullable|string', // Appended to description
        ]);

        try {
            DB::beginTransaction();

            // 1. Create the Admin User
            $adminUser = User::create([
                'role' => 'admin',
                'name' => $request->full_name,
                'email' => $request->email,
                'phone' => $request->phone_number,
                'password_hash' => Hash::make($request->password),
            ]);

            // 2. Format Address & Description
            $fullAddress = $request->street_address;
            $fullDescription = $request->description ?? '';

            // 3. Generate unique slug for Salon
            $slug = Str::slug($request->salon_name);
            if (Salon::where('slug', $slug)->exists()) {
                $slug = $slug . '-' . uniqid();
            }

            // 4. Create the Salon
            $salon = Salon::create([
                'admin_id' => $adminUser->id,
                'name' => $request->salon_name,
                'slug' => $slug,
                'description' => trim($fullDescription),
                'city_id' => $request->city_id,
                'address' => $fullAddress,
                'pincode' => $request->pincode,
                'latitude' => $request->latitude,
                'longitude' => $request->longitude,
                // Only the owner standing in their own salon can claim 'owner'.
                'location_source' => $request->filled(['latitude', 'longitude'])
                    ? 'owner'
                    : null,
                'status' => 'pending_approval',
                'submitted_by' => $adminUser->id,
                'advance_required' => true,
                'advance_refundable' => false,
                'advance_percentage_default' => 25.00,
                'gender_focus' => $request->gender_focus ?? 'Unisex',
            ]);

            DB::commit();

            return response()->json([
                'message' => 'Salon registered successfully. Pending SuperAdmin approval.',
                'user' => $adminUser,
                'salon' => $salon
            ], 201);

        } catch (\Exception $e) {
            DB::rollBack();
            return response()->json([
                'message' => 'Failed to register salon.',
                'error' => $e->getMessage()
            ], 500);
        }
    }
}
