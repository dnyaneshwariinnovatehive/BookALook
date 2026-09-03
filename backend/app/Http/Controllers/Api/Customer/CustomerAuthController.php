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
}
