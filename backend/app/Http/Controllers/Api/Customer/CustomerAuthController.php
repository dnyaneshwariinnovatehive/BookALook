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

        // In a real application, you would integrate an SMS gateway (like Twilio or AWS SNS) here.
        // For now, we mock the OTP as '123456'.
        $mockedOtp = '123456';
        
        // Normally you'd store this OTP in the cache or database tied to the phone number with an expiration.
        // Cache::put('otp_' . $phone, $mockedOtp, now()->addMinutes(5));

        return response()->json([
            'message' => 'OTP sent successfully. For testing, use 123456.',
            'phone' => $phone
        ]);
    }

    /**
     * Verify OTP and login or register the customer.
     */
    public function verifyOtp(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'phone' => 'required|string|max:15',
            'otp' => 'required|string|size:6',
            'name' => 'nullable|string|max:150', // Required if registering
            'gender' => 'nullable|in:male,female,other,unspecified', // Required if registering
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        // Validate the OTP (Mocked validation)
        // $cachedOtp = Cache::get('otp_' . $request->phone);
        // if ($request->otp !== $cachedOtp) {
        if ($request->otp !== '123456') {
            throw ValidationException::withMessages([
                'otp' => ['The provided OTP is incorrect.'],
            ]);
        }

        // Cache::forget('otp_' . $request->phone);

        $user = User::where('phone', $request->phone)->first();

        // If user doesn't exist, we register them
        if (!$user) {
            if (!$request->name) {
                return response()->json([
                    'message' => 'Registration required. Please provide name and optionally gender.',
                    'requires_registration' => true
                ], 200); // Or 428 Precondition Required
            }

            $user = User::create([
                'role' => 'customer',
                'name' => $request->name,
                'phone' => $request->phone,
                'password_hash' => Hash::make(str()->random(16)), // Assign random password hash as we rely on OTP
                'gender' => $request->gender ?? 'unspecified',
                'is_active' => true,
            ]);
        }

        // Log the user in via Sanctum token
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
     * Logout the customer.
     */
    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json([
            'message' => 'Logged out successfully.'
        ]);
    }
}
