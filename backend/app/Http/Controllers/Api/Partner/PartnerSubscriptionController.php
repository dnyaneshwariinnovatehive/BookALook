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
use App\Services\CommissionService;
use App\Support\BillingModel;
use Carbon\Carbon;
use CloudinaryLabs\CloudinaryLaravel\Facades\Cloudinary;
use Illuminate\Support\Facades\DB;

/**
 * How a salon owner sees and changes the way they pay.
 *
 * Two arrangements, and they are not interchangeable from here. A Subscription
 * Plan is bought — the owner transfers the money and uploads the receipt, and
 * SuperAdmin verifies it. The Commission Model is agreed — the owner asks for
 * it and SuperAdmin sets the percentage, because a salon cannot set what it
 * will be charged.
 */
class PartnerSubscriptionController extends Controller
{
    public function __construct(private CommissionService $commission)
    {
    }

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

        $model = $salon->billingModel();
        $onCommission = $salon->isOnCommissionModel();

        return response()->json([
            'success' => true,
            'has_subscription' => $subscription ? true : false,
            'subscription' => $subscription,
            'billing_model' => $model,
            'billing_label' => BillingModel::label($model),
            'commission_percentage' => $onCommission ? (float) ($salon->commission_percentage ?? 0) : null,
            // Postpaid: there is nothing to renew, only a month to settle.
            'can_renew' => ! $onCommission,
            'next_settlement_date' => $onCommission
                ? Carbon::today()->addMonthNoOverflow()->startOfMonth()->toDateString()
                : null,
            'days_remaining' => $daysRemaining,
            'warning_threshold_days' => $warningDays,
            'pending_request' => $pendingRequest,
            'history' => $history
        ]);
    }

    public function getPlans(Request $request)
    {
        $plans = SubscriptionPlan::purchasable()->orderBy('price')->get();
        $commissionPlan = $this->commission->plan();

        return response()->json([
            'success' => true,
            'plans' => $plans,
            'commission_model' => $commissionPlan ? [
                'available' => true,
                'plan_name' => $commissionPlan->name,
                'plan' => $commissionPlan,
                'description' => 'Pay nothing up front. SuperAdmin agrees a percentage of what you bill, '
                    . 'settled on the 1st of each month for the month just finished.',
            ] : ['available' => false],
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
            $newSub = DB::transaction(function () use ($salon, $salonId, $plan, $quote, $request, $wallet) {
                SalonSubscription::where('salon_id', $salonId)
                    ->where('status', 'active')
                    ->update(['status' => 'cancelled', 'cancelled_at' => Carbon::now()]);

                // Buying a plan is leaving the Commission Model. The rate is
                // closed rather than dropped, because payouts already settled
                // against it still have to be explainable.
                if ($salon->isOnCommissionModel()) {
                    $this->commission->deactivate($salon, $request->user());
                }

                // The salon_subscriptions schema uses plan_id (a UUID), not
                // subscription_plan_id. Keep the price and plan duration as a snapshot.
                $subscription = SalonSubscription::create([
                    'salon_id' => $salonId,
                    'plan_id' => $plan->id,
                    'plan_price_snapshot' => $plan->price,
                    'status' => 'active',
                    'start_date' => Carbon::today(),
                    'end_date' => Carbon::today()->addDays($plan->validity_days),
                    'billing_type' => BillingModel::SUBSCRIPTION,
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

        // Nothing was bought, so nothing can be renewed. Access on the
        // Commission Model is extended by settling the month, not by this.
        if ($salon->isOnCommissionModel()) {
            return response()->json([
                'success' => false,
                'message' => 'You are on the Commission Model. There is nothing to renew — '
                    . 'your access extends when the month’s commission is settled.',
            ], 422);
        }

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

    /**
     * Buy a Subscription Plan: the owner transfers the money and uploads proof.
     */
    public function paymentRequest(Request $request, $salon_id)
    {
        $request->validate([
            'screenshot' => 'required|image|mimes:jpeg,png,jpg|max:5120',
            'plan_id' => 'required|exists:subscription_plans,id',
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
            'billing_type' => BillingModel::SUBSCRIPTION,
            'screenshot_url' => $uploadedFileUrl,
            'status' => 'pending'
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Payment screenshot uploaded successfully. Your subscription plan will be activated once verified by SuperAdmin.',
            'data' => $paymentRequest
        ]);
    }

    /**
     * Ask to move onto the Commission Model.
     *
     * Nothing is paid, so there is no receipt to upload — and the salon does
     * not name its own percentage. SuperAdmin agrees the rate when approving,
     * which is the only reason this is a request rather than a switch.
     */
    public function commissionRequest(Request $request, $salon_id)
    {
        $user = $request->user();
        $salon = Salon::where('admin_id', $user->id)->findOrFail($salon_id);

        if ($salon->isOnCommissionModel()) {
            return response()->json([
                'success' => false,
                'message' => 'This salon is already on the Commission Model.',
            ], 422);
        }

        if (! $this->commission->plan()) {
            return response()->json([
                'success' => false,
                'message' => 'The Commission Model is not open for sign-up yet. Please contact support.',
            ], 422);
        }

        SubscriptionPaymentRequest::where('salon_id', $salon->id)
            ->where('status', 'pending')
            ->update(['status' => 'rejected']);

        $commissionRequest = SubscriptionPaymentRequest::create([
            'salon_id' => $salon->id,
            'subscription_plan_id' => $this->commission->plan()->id,
            'billing_type' => BillingModel::COMMISSION,
            'screenshot_url' => null,
            'status' => 'pending',
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Request sent. SuperAdmin will confirm your commission percentage and switch you over.',
            'data' => $commissionRequest,
        ]);
    }
}
