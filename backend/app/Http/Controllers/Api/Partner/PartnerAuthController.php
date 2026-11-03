<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\User;
use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Models\WhatsappAutomation;
use App\Models\WhatsAppMessage;
use App\Jobs\SendWhatsAppMessageJob;
use App\Services\Auth\LoginOtp;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;

class PartnerAuthController extends Controller
{
    public function sendOtp(Request $request)
    {
        $request->validate([
            'phone' => 'required|string',
        ]);

        $phone = $request->phone;
        $otps = app(LoginOtp::class);

        // A store-review number has a fixed code and is never sent one.
        if ($otps->isReviewPhone($phone)) {
            return response()->json(['status' => 'success', 'message' => 'OTP sent successfully.']);
        }

        $automation = WhatsappAutomation::where('key', 'whatsapp_otp')->first();

        // If WhatsApp OTP is enabled and has a configured campaign, send real OTP via WhatsApp
        if ($automation && $automation->is_enabled && !empty($automation->aisensy_campaign_name)) {
            $otp = str_pad((string) random_int(100000, 999999), 6, '0', STR_PAD_LEFT);
            $otps->issue(LoginOtp::PARTNER, $phone, $otp);

            $message = WhatsAppMessage::create([
                'to_phone' => $phone,
                'template' => $automation->key,
                'campaign' => $automation->aisensy_campaign_name,
                'payload' => ['parameters' => [$otp]],
                'status' => WhatsAppMessage::STATUS_QUEUED,
                'category' => 'authentication',
            ]);

            SendWhatsAppMessageJob::dispatch($message->id);

            return response()->json([
                'status' => 'success',
                'message' => 'OTP sent successfully to your WhatsApp number.',
            ]);
        }

        // WhatsApp OTP off: the demo code, outside production only.
        $demo = $otps->demoCode();
        if ($demo === null) {
            return response()->json([
                'status' => 'error',
                'message' => 'Login codes cannot be sent right now. Please try again later.',
            ], 503);
        }
        $otps->issue(LoginOtp::PARTNER, $phone, $demo);

        return response()->json([
            'status' => 'success',
            'message' => "OTP sent successfully (Use {$demo} for testing)",
        ]);
    }

    /** Reached only with a login that still works; an expired one gets a 401. */
    public function check()
    {
        return response()->json(['success' => true]);
    }

    public function verifyOtp(Request $request)
    {
        $request->validate([
            'phone' => 'required|string',
            'otp' => 'required|string',
        ]);

        // Only the code sent to this phone (the demo code when WhatsApp OTP is
        // off). Five wrong guesses discard it.
        if (! app(LoginOtp::class)->check(LoginOtp::PARTNER, $request->phone, $request->otp)) {
            return response()->json([
                'success' => false,
                'message' => 'Invalid OTP',
            ], 400);
        }


        $user = User::where('phone', $request->phone)
            ->whereIn('role', ['admin', 'service_provider', 'collaborator'])
            ->first();

        if (!$user) {
            $enquiry = \App\Models\SalonEnquiry::where('phone', $request->phone)
                ->where('status', 'assigned')
                ->latest()
                ->first();

            return response()->json([
                'success' => true,
                'status' => 'new_user',
                'message' => 'User not found or not a partner. Redirect to registration.',
                'enquiry' => $enquiry,
            ]);
        }

        $token = $user->createToken('partner-auth-token')->plainTextToken;

        if ($user->role === 'admin') {
            $salons = Salon::with(['city:id,name', 'admin:id,name,phone'])
                ->where('admin_id', $user->id)
                ->get();
            
            return response()->json([
                'success' => true,
                'status' => 'existing_user',
                'role' => 'admin',
                'salons' => $salons,
                'token' => $token,
                'user' => $user,
            ]);
        } elseif ($user->role === 'service_provider') {
            $serviceProvider = ServiceProvider::with(['services.template', 'workingHours'])->where('user_id', $user->id)->first();
            
            if (!$serviceProvider) {
                 return response()->json([
                    'success' => false,
                    'message' => 'Service provider profile not found.',
                ], 404);
            }

            $salon = Salon::with(['city:id,name', 'admin:id,name,phone'])
                ->where('id', $serviceProvider->salon_id)
                ->first();

            return response()->json([
                'success' => true,
                'status' => 'existing_user',
                'role' => 'service_provider',
                'salon' => $salon,
                'token' => $token,
                'user' => $user,
                'provider' => $serviceProvider,
            ]);
        } elseif ($user->role === 'collaborator') {
            return response()->json([
                'success' => true,
                'status' => 'existing_user',
                'role' => 'collaborator',
                'token' => $token,
                'user' => $user,
            ]);
        }

        return response()->json([
            'success' => false,
            'message' => 'Unauthorized role.',
        ], 403);
    }
}
