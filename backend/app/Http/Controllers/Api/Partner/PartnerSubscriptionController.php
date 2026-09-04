<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\PlatformPolicySetting;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPlan;
use App\Models\SalonWallet;
use App\Models\WalletScheme;
use App\Models\SubscriptionPaymentRequest;
use Carbon\Carbon;
use CloudinaryLabs\CloudinaryLaravel\Facades\Cloudinary;

class PartnerSubscriptionController extends Controller
{
    public function getSubscription(Request $request)
    {
        $user = $request->user();
        $salonId = $user->salon_id ?? 1;

        $subscription = SalonSubscription::with('plan')->where('salon_id', $salonId)->where('status', 'active')->first();
        
        $policy = PlatformPolicySetting::where('setting_key', 'subscription_expiry_warning_days')->first();
        $warningDays = $policy ? (int)$policy->setting_value : 3;

        $daysRemaining = 0;
        if ($subscription && $subscription->end_date) {
            $daysRemaining = Carbon::now()->diffInDays(Carbon::parse($subscription->end_date), false);
        }

        $pendingRequest = SubscriptionPaymentRequest::with('plan')
            ->where('salon_id', $salonId)
            ->where('status', 'pending')
            ->first();

        return response()->json([
            'success' => true,
            'has_subscription' => $subscription ? true : false,
            'subscription' => $subscription,
            'days_remaining' => $daysRemaining,
            'warning_threshold_days' => $warningDays,
            'pending_request' => $pendingRequest
        ]);
    }

    public function upgradeSubscription(Request $request)
    {
        $request->validate([
            'plan_id' => 'required|exists:subscription_plans,id',
            'apply_coins' => 'boolean'
        ]);

        $user = $request->user();
        $salonId = $user->salon_id ?? 1;

        $plan = SubscriptionPlan::findOrFail($request->plan_id);
        $wallet = SalonWallet::firstOrCreate(['salon_id' => $salonId], ['balance' => 0]);
        $scheme = WalletScheme::where('is_active', true)->first();
        $coinValue = $scheme ? $scheme->coin_value : 0;

        $price = $plan->price;
        $discount = 0;
        $coinsApplied = 0;

        if ($request->apply_coins && $wallet->balance > 0 && $coinValue > 0) {
            $maxCoinsValue = $wallet->balance * $coinValue;
            
            if ($maxCoinsValue >= $price) {
                // Costs zero, deduct partial coins
                $coinsApplied = ceil($price / $coinValue);
                $discount = $price;
            } else {
                // Costs > 0, deduct all coins
                $coinsApplied = $wallet->balance;
                $discount = $maxCoinsValue;
            }
        }

        $finalPrice = max(0, $price - $discount);

        // MOCK PAYMENT PROCESS
        // If this were real, we'd create an intent and return client_secret.
        // For now, process immediately.
        
        if ($coinsApplied > 0) {
            $wallet->balance -= $coinsApplied;
            $wallet->save();

            $wallet->transactions()->create([
                'type' => 'redeemed',
                'amount' => $coinsApplied,
                'description' => "Redeemed for subscription upgrade to {$plan->name}"
            ]);
        }

        // Cancel old sub
        SalonSubscription::where('salon_id', $salonId)->where('status', 'active')->update(['status' => 'cancelled']);

        // Create new sub
        $newSub = SalonSubscription::create([
            'salon_id' => $salonId,
            'subscription_plan_id' => $plan->id,
            'status' => 'active',
            'start_date' => Carbon::now(),
            'end_date' => Carbon::now()->addMonth(),
            'feature_level' => 'growth', // Simplified for demo
            'billing_type' => 'flat'
        ]);

        return response()->json([
            'success' => true,
            'message' => "Successfully upgraded to {$plan->name}. Total paid: ₹{$finalPrice}.",
            'subscription' => $newSub
        ]);
    }

    public function renew(Request $request)
    {
        // Simple mock renew for the existing button
        $user = $request->user();
        $salonId = $user->salon_id ?? 1;

        $subscription = SalonSubscription::where('salon_id', $salonId)->where('status', 'active')->first();
        if ($subscription) {
            $subscription->end_date = Carbon::parse($subscription->end_date)->addMonth();
            $subscription->save();
        }
        
        return response()->json([
            'success' => true,
            'message' => 'Subscription renewed successfully'
        ]);
    }

    public function paymentRequest(Request $request)
    {
        $request->validate([
            'screenshot' => 'required|image|mimes:jpeg,png,jpg|max:5120',
            'plan_id' => 'required|exists:subscription_plans,id',
            'billing_type' => 'required|in:flat,commission'
        ]);

        $user = $request->user();
        $salonId = $user->salon_id ?? 1;

        // Cancel previous pending requests to avoid duplicates
        SubscriptionPaymentRequest::where('salon_id', $salonId)
            ->where('status', 'pending')
            ->update(['status' => 'rejected']);

        $uploadedFileUrl = Cloudinary::upload($request->file('screenshot')->getRealPath())->getSecurePath();

        $paymentRequest = SubscriptionPaymentRequest::create([
            'salon_id' => $salonId,
            'subscription_plan_id' => $request->plan_id,
            'billing_type' => $request->billing_type,
            'screenshot_url' => $uploadedFileUrl,
            'status' => 'pending'
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Payment screenshot uploaded successfully. Your subscription will be activated once verified by SuperAdmin.',
            'data' => $paymentRequest
        ]);
    }
}
