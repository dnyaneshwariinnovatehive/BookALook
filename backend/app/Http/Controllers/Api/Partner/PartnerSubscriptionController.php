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
    public function getSubscription(Request $request, $salon_id)
    {
        $user = $request->user();
        $salon = Salon::where('admin_id', $user->id)->findOrFail($salon_id);

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

    public function upgradeSubscription(Request $request, $salon_id)
    {
        $request->validate([
            'plan_id' => 'required|exists:subscription_plans,id',
            'apply_coins' => 'boolean'
        ]);

        $user = $request->user();
        $salon = Salon::where('admin_id', $user->id)->findOrFail($salon_id);

        if (!$salon) {
            return response()->json(['success' => false, 'message' => 'Salon not found'], 404);
        }
        $salonId = $salon->id;

        $plan = SubscriptionPlan::findOrFail($request->plan_id);
        $wallet = app(\App\Services\WalletService::class);

        $price = (float) $plan->price;

        // Coins are only worth what they cover; never spend more than the plan.
        $quote = $request->boolean('apply_coins')
            ? $wallet->quote($salonId, $price)
            : ['coins' => 0, 'value' => 0.0];

        $finalPrice = round(max($price - $quote['value'], 0), 2);

        try {
            // Coins leave the wallet inside the same transaction that creates
            // the subscription, so a failed purchase cannot swallow them.
            $newSub = DB::transaction(function () use ($salonId, $plan, $quote, $request, $wallet) {
                SalonSubscription::where('salon_id', $salonId)
                    ->where('status', 'active')
                    ->update(['status' => 'cancelled', 'cancelled_at' => Carbon::now()]);

                // The salon_subscriptions schema uses plan_id (a UUID), not
                // subscription_plan_id. Keep the price and plan duration as a snapshot.
                $subscription = SalonSubscription::create([
                    'salon_id' => $salonId,
                    'plan_id' => $plan->id,
                    'plan_price_snapshot' => $plan->price,
                    'status' => 'active',
                    'start_date' => Carbon::today(),
                    'end_date' => Carbon::today()->addDays($plan->validity_days),
                    'billing_type' => 'flat',
                ]);

                if ($quote['coins'] > 0) {
                    $wallet->redeemForSubscription(
                        $salonId,
                        $quote['coins'],
                        (float) $plan->price,
                        $request->user(),
                        $subscription,
                        "Applied to {$plan->name}"
                    );
                }

                return $subscription;
            });
        } catch (\RuntimeException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], 422);
        }

        return response()->json([
            'success' => true,
            'message' => "Successfully upgraded to {$plan->name}. Total paid: " . $finalPrice . '.',
            'coins_redeemed' => $quote['coins'],
            'coin_discount' => $quote['value'],
            'amount_payable' => $finalPrice,
            'subscription' => $newSub,
        ]);
    }

    public function renew(Request $request, $salon_id)
    {
        // Simple mock renew for the existing button
        $user = $request->user();
        $salon = Salon::where('admin_id', $user->id)->findOrFail($salon_id);

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

    public function paymentRequest(Request $request, $salon_id)
    {
        $request->validate([
            'screenshot' => 'required|image|mimes:jpeg,png,jpg|max:5120',
            'plan_id' => 'required|exists:subscription_plans,id',
            'billing_type' => 'required|in:flat,commission'
        ]);

        $user = $request->user();
        $salon = Salon::where('admin_id', $user->id)->findOrFail($salon_id);

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
