<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\User;
use App\Models\Salon;
use App\Models\ServiceProvider;
use Illuminate\Support\Facades\DB;

class PartnerAuthController extends Controller
{
    public function sendOtp(Request $request)
    {
        $request->validate([
            'phone' => 'required|string',
        ]);

        // In a real application, generate and send an OTP via SMS provider.
        // For development, we just pretend it was successful and use '123456'.

        return response()->json([
            'status' => 'success',
            'message' => 'OTP sent successfully (Use 123456 for testing)',
        ]);
    }

    public function verifyOtp(Request $request)
    {
        $request->validate([
            'phone' => 'required|string',
            'otp' => 'required|string',
        ]);

        if ($request->otp !== '123456') {
            return response()->json([
                'success' => false,
                'message' => 'Invalid OTP',
            ], 400);
        }

        $user = User::where('phone', $request->phone)
            ->whereIn('role', ['admin', 'service_provider'])
            ->first();

        if (!$user) {
            return response()->json([
                'success' => true,
                'status' => 'new_user',
                'message' => 'User not found or not a partner. Redirect to registration.',
            ]);
        }

        $token = $user->createToken('partner-auth-token')->plainTextToken;

        if ($user->role === 'admin') {
            $salons = Salon::where('admin_id', $user->id)->get(['id', 'name', 'cover_photo_url', 'city', 'status']);
            
            return response()->json([
                'success' => true,
                'status' => 'existing_user',
                'role' => 'admin',
                'salons' => $salons,
                'token' => $token,
                'user' => $user,
            ]);
        } elseif ($user->role === 'service_provider') {
            $serviceProvider = ServiceProvider::with(['services', 'workingHours'])->where('user_id', $user->id)->first();
            
            if (!$serviceProvider) {
                 return response()->json([
                    'success' => false,
                    'message' => 'Service provider profile not found.',
                ], 404);
            }

            $salon = Salon::where('id', $serviceProvider->salon_id)->first(['id', 'name', 'cover_photo_url', 'city', 'status']);

            return response()->json([
                'success' => true,
                'status' => 'existing_user',
                'role' => 'service_provider',
                'salon' => $salon,
                'token' => $token,
                'user' => $user,
                'provider' => $serviceProvider,
            ]);
        }

        return response()->json([
            'success' => false,
            'message' => 'Unauthorized role.',
        ], 403);
    }
}
