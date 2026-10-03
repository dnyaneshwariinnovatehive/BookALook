<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

class CustomerAuthController extends Controller
{
    /**
     * Send OTP for login or registration.
     */
    public function sendOtp(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'phone' => 'required|string|max:15',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $phone = $request->phone;

        // Mock OTP
        $mockedOtp = '123456';
        
        \Illuminate\Support\Facades\Cache::put('otp_' . $phone, $mockedOtp, now()->addMinutes(10));

        return response()->json([
            'message' => 'OTP sent successfully. For testing, use 123456.',
            'phone' => $phone
        ]);
    }

    /**
     * Verify OTP.
     */
    public function verifyOtp(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'phone' => 'required|string|max:15',
            'otp' => 'required|string|size:6',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $cachedOtp = \Illuminate\Support\Facades\Cache::get('otp_' . $request->phone);
        
        // Mock verification for testing without cache
        if ($request->otp !== '123456' && $request->otp !== $cachedOtp) {
            throw ValidationException::withMessages([
                'otp' => ['The provided OTP is incorrect.'],
            ]);
        }

        \Illuminate\Support\Facades\Cache::forget('otp_' . $request->phone);
        \Illuminate\Support\Facades\Cache::put('verified_phone_' . $request->phone, true, now()->addMinutes(15));

        $user = User::where('phone', $request->phone)->first();

        if ($user && $user->role !== 'customer') {
            return response()->json([
                'message' => 'This account is registered as a partner. Please use the Partner App to log in.',
            ], 403);
        }

        if (!$user) {
            return response()->json([
                'message' => 'OTP verified. Profile completion required.',
                'requires_registration' => true,
                'phone' => $request->phone
            ]);
        }

        $user->last_login_at = now();
        $user->save();
        $token = $user->createToken('customer_app')->plainTextToken;

        return response()->json([
            'message' => 'Authentication successful.',
            'access_token' => $token,
            'token_type' => 'Bearer',
            'user' => $user
        ]);
    }

    /**
     * Complete profile for new users.
     */
    public function completeProfile(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'phone' => 'required|string|max:15',
            'name' => 'required|string|max:150',
            'gender' => 'nullable|in:male,female,other,unspecified',
            'date_of_birth' => 'nullable|date',
            'address' => 'nullable|string',
            'pincode' => 'nullable|string|max:10',
            // Where they are. Required at sign-up so the app can show what is
            // actually near them from the first screen — a city alone covers a
            // two-hour drive and answers nothing useful.
            'city_id' => 'required|exists:cities,id',
            'sub_area_id' => [
                'required', 'uuid',
                \Illuminate\Validation\Rule::exists('sub_areas', 'id')->where(
                    fn ($q) => $q->where('city_id', $request->city_id)
                ),
            ],
        ], [
            'city_id.required' => 'Please choose your city.',
            'sub_area_id.required' => 'Please choose your area.',
            'sub_area_id.exists' => 'That area is not in the city you picked.',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        if (!\Illuminate\Support\Facades\Cache::get('verified_phone_' . $request->phone)) {
            return response()->json(['message' => 'Phone number not verified or verification expired.'], 403);
        }

        $user = User::where('phone', $request->phone)->first();
        if ($user) {
            return response()->json(['message' => 'User already exists.'], 400);
        }

        $user = User::create([
            'role' => 'customer',
            'name' => $request->name,
            'phone' => $request->phone,
            'password_hash' => Hash::make(str()->random(16)),
            'gender' => $request->gender ?? 'unspecified',
            'date_of_birth' => $request->date_of_birth,
            'address' => $request->address,
            'pincode' => $request->pincode,
            'city_id' => $request->city_id,
            'sub_area_id' => $request->sub_area_id,
            'is_active' => true,
            'last_login_at' => now(),
        ]);

        \Illuminate\Support\Facades\Cache::forget('verified_phone_' . $request->phone);

        $token = $user->createToken('customer_app')->plainTextToken;

        return response()->json([
            'message' => 'Profile completed and authenticated.',
            'access_token' => $token,
            'token_type' => 'Bearer',
            'user' => $user
        ]);
    }

    /**
     * Logout the customer.
     */
    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json([
            'message' => 'Logged out successfully.'
        ]);
    }

    /**
     * Get customer profile and stats.
     */
    /**
     * Update customer profile.
     */
    public function updateProfile(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'name' => 'sometimes|string|max:150',
            'phone' => 'sometimes|string|max:15',
            'email' => 'nullable|email|max:255',
            'gender' => 'nullable|in:male,female,other,unspecified',
            'date_of_birth' => 'nullable|date',
            'address' => 'nullable|string',
            'pincode' => 'nullable|string|max:10',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $user = $request->user();

        if ($request->has('phone') && $request->phone !== $user->phone) {
            $existingUser = User::where('phone', $request->phone)->first();
            if ($existingUser) {
                return response()->json(['message' => 'This phone number is already registered.'], 400);
            }
            $user->phone = $request->phone;
        }

        if ($request->has('name')) $user->name = $request->name;
        if ($request->has('email')) $user->email = $request->email;
        if ($request->has('gender')) $user->gender = $request->gender;
        if ($request->has('date_of_birth')) $user->date_of_birth = $request->date_of_birth;
        if ($request->has('address')) $user->address = $request->address;
        if ($request->has('pincode')) $user->pincode = $request->pincode;

        $user->save();

        return response()->json([
            'message' => 'Profile updated successfully.',
            'user' => $user
        ]);
    }

    /**
     * Change the city this customer browses in.
     *
     * Separate from the rest of the profile because it is changed far more
     * often — a customer switches market from the home screen, not by editing
     * their details.
     */
    public function updateCity(Request $request)
    {
        $request->validate([
            'city_id' => 'required|exists:cities,id',
            // Optional: the app may switch city and area together, or just the
            // city and let them pick an area afterwards.
            'sub_area_id' => [
                'nullable', 'uuid',
                \Illuminate\Validation\Rule::exists('sub_areas', 'id')->where(
                    fn ($q) => $q->where('city_id', $request->city_id)
                ),
            ],
        ]);

        $user = $request->user();
        $movedCity = $user->city_id !== $request->city_id;

        $user->forceFill([
            'city_id' => $request->city_id,
            // An area from the old city would now be somewhere else entirely,
            // so changing city drops it unless a new one came with the request.
            'sub_area_id' => $request->sub_area_id ?? ($movedCity ? null : $user->sub_area_id),
        ])->save();

        return response()->json([
            'success' => true,
            'city' => $user->fresh()->city,
            'sub_area' => $user->fresh()->subArea,
        ]);
    }

    public function profile(Request $request)
    {
        $user = $request->user();
        $user->loadMissing(['city', 'subArea']);

        // Count of all non-cancelled appointments booked by this customer
        $appointmentsCount = \App\Models\Appointment::where('customer_id', $user->id)
            ->where('status', '!=', 'cancelled')
            ->count();

        return response()->json([
            'user' => $user,
            'appointments_count' => $appointmentsCount,
            'fav_salons_count' => $user->favouriteSalons()->count(),
        ]);
    }

    /**
     * Delete the customer account.
     * Anonymizes PII to allow future re-registration while maintaining structural
     * integrity for financial records (appointments, payments).
     */
    public function deleteAccount(Request $request)
    {
        $user = $request->user();

        // 1. Revoke all active sessions/tokens
        $user->tokens()->delete();

        // 2. Anonymize PII. Phone is limited to 15 chars, so 'del_' + 11 random chars = 15
        $user->update([
            'name' => 'Deleted User',
            'phone' => 'del_' . str()->random(11),
            'email' => $user->email ? 'del_' . str()->random(10) . '@example.com' : null,
            'address' => null,
            'pincode' => null,
            'date_of_birth' => null,
            'is_active' => false,
        ]);

        // 3. Soft delete the user
        $user->delete();

        return response()->json([
            'message' => 'Account deleted successfully.'
        ]);
    }
}
