<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\PlatformPolicySetting;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPlan;
use App\Models\SalonWallet;
use App\Models\WalletScheme;
use App\Models\SubscriptionPaymentRequest;
use Carbon\Carbon;
use CloudinaryLabs\CloudinaryLaravel\Facades\Cloudinary;
use Illuminate\Support\Facades\DB;

class PartnerSubscriptionController extends Controller
{
    public function getSubscription(Request $request)
    {
        $user = $request->user();
        $salon = Salon::where('admin_id', $user->id)->first();

        if (!$salon) {
            return response()->json(['success' => false, 'message' => 'Salon not found'], 404);
        }
        $salonId = $salon->id;

        // Do not rely solely on the scheduled expiry job for what a partner sees.
        // This keeps an expired plan from being returned as active between scheduled runs.
        SalonSubscription::where('salon_id', $salonId)
            ->where('status', 'active')
            ->whereDate('end_date', '<', Carbon::today())
            ->update(['status' => 'expired']);

        $subscription = $salon->currentSubscription()->with('plan')->first();

        $policy = PlatformPolicySetting::where('setting_key', 'subscription_expiry_warning_days')->first();
        $warningDays = $policy ? (int)$policy->setting_value : 3;

        $daysRemaining = 0;
        if ($subscription && $subscription->end_date) {
            $daysRemaining = Carbon::now()->startOfDay()->diffInDays(Carbon::parse($subscription->end_date), false);
        }

        $pendingRequest = SubscriptionPaymentRequest::with('plan')
            ->where('salon_id', $salonId)
            ->where('status', 'pending')
            ->first();

        $history = $salon->subscriptions()->with('plan')->orderBy('created_at', 'desc')->get();

        return response()->json([
            'success' => true,
            'has_subscription' => $subscription ? true : false,
            'subscription' => $subscription,
            'days_remaining' => $daysRemaining,
            'warning_threshold_days' => $warningDays,
            'pending_request' => $pendingRequest,
            'history' => $history
        ]);
    }

    public function getPlans()
    {
        $plans = SubscriptionPlan::where('is_active', true)->get();
        return response()->json([
            'success' => true,
            'plans' => $plans
        ]);
    }

    public function upgradeSubscription(Request $request)
    {
        $request->validate([
            'plan_id' => 'required|exists:subscription_plans,id',
            'apply_coins' => 'boolean'
        ]);

        $user = $request->user();
        $salon = Salon::where('admin_id', $user->id)->first();

        if (!$salon) {
            return response()->json(['success' => false, 'message' => 'Salon not found'], 404);
        }
        $salonId = $salon->id;

        $plan = SubscriptionPlan::findOrFail($request->plan_id);
        $wallet = SalonWallet::firstOrCreate(['salon_id' => $salonId], ['coin_balance' => 0]);
        $scheme = WalletScheme::where('is_active', true)->first();
        $coinValue = $scheme ? $scheme->coin_value : 0;

        $price = $plan->price;
        $discount = 0;
        $coinsApplied = 0;

        if ($request->apply_coins && $wallet->coin_balance > 0 && $coinValue > 0) {
            $maxCoinsValue = $wallet->coin_balance * $coinValue;
            
            if ($maxCoinsValue >= $price) {
                // Costs zero, deduct partial coins
                $coinsApplied = ceil($price / $coinValue);
                $discount = $price;
            } else {
                // Costs > 0, deduct all coins
                $coinsApplied = $wallet->coin_balance;
                $discount = $maxCoinsValue;
            }
        }

        $finalPrice = max(0, $price - $discount);

        // MOCK PAYMENT PROCESS
        // If this were real, we'd create an intent and return client_secret.
        // For now, process immediately.

        if ($coinsApplied > 0) {
            $wallet->coin_balance -= $coinsApplied;
            $wallet->save();

            $wallet->transactions()->create([
                'type' => 'redeemed',
                'amount' => $coinsApplied,
                'description' => "Redeemed for subscription upgrade to {$plan->name}"
            ]);
        }

        $newSub = DB::transaction(function () use ($salonId, $plan) {
            // Cancel old sub
            SalonSubscription::where('salon_id', $salonId)
                ->where('status', 'active')
                ->update(['status' => 'cancelled', 'cancelled_at' => Carbon::now()]);

            // The salon_subscriptions schema uses plan_id (a UUID), not
            // subscription_plan_id. Keep the price and plan duration as a snapshot.
            return SalonSubscription::create([
                'salon_id' => $salonId,
                'plan_id' => $plan->id,
                'plan_price_snapshot' => $plan->price,
                'status' => 'active',
                'start_date' => Carbon::today(),
                'end_date' => Carbon::today()->addDays($plan->validity_days),
                'billing_type' => 'flat',
            ]);
        });

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
        $salon = Salon::where('admin_id', $user->id)->first();

        if (!$salon) {
            return response()->json(['success' => false, 'message' => 'Salon not found'], 404);
        }
        $salonId = $salon->id;

        $subscription = SalonSubscription::where('salon_id', $salonId)
            ->where('status', 'active')
            ->latest('start_date')
            ->first();
        if ($subscription) {
            $plan = $subscription->plan;
            $subscription->end_date = Carbon::parse($subscription->end_date)
                ->addDays($plan?->validity_days ?? 30);
            $subscription->save();
        } else {
            return response()->json(['success' => false, 'message' => 'No active subscription to renew'], 404);
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
        $salon = Salon::where('admin_id', $user->id)->first();

        if (!$salon) {
            return response()->json(['success' => false, 'message' => 'Salon not found'], 404);
        }
        $salonId = $salon->id;

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
