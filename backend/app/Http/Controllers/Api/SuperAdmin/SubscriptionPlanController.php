<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPaymentRequest;
use App\Models\SubscriptionPlan;
use App\Services\CommissionService;
use App\Support\BillingModel;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

/**
 * Plans, and which arrangement each salon trades under.
 *
 * A salon is on exactly one of two things. Either it buys a Subscription Plan,
 * which is prepaid and expires, or it is on the Commission Model, which is
 * postpaid and settled monthly. The second is not a plan the salon buys — it is
 * one nominated plan's benefits, granted to every commission salon alike, with
 * a per-salon percentage SuperAdmin sets.
 */
class SubscriptionPlanController extends Controller
{
    public function __construct(private CommissionService $commission)
    {
    }

    /**
     * Plans, the nominated Commission Model plan, and where every salon stands.
     */
    public function index()
    {
        $plans = SubscriptionPlan::orderByDesc('is_commission_plan')->orderBy('price')->get();

        $salons = Salon::with(['currentSubscription.plan', 'admin'])->get()->map(function (Salon $salon) {
            $model = $salon->billingModel();
            $subscription = $salon->currentSubscription;

            return [
                'id' => $salon->id,
                'name' => $salon->name,
                'owner' => $salon->admin->name ?? 'Unknown',
                'billing_model' => $model,
                'billing_label' => BillingModel::label($model),
                'current_plan' => $subscription?->plan->name ?? 'None',
                'commission_percentage' => $salon->isOnCommissionModel()
                    ? (float) ($salon->commission_percentage ?? 0)
                    : null,
                'commission_rate_effective_from' => $salon->commission_rate_effective_from?->toDateString(),
                // A rate cannot move while money is still owed on the old one,
                // so the dashboard needs to know before offering the control.
                'unsettled_payouts' => $salon->isOnCommissionModel()
                    ? $this->commission->unsettledPayouts($salon->id)->count()
                    : 0,
                'expiry' => $subscription?->end_date?->format('Y-m-d'),
                'status' => $subscription->status ?? 'N/A',
            ];
        })->values();

        $commissionPlan = $this->commission->plan();

        return response()->json([
            'success' => true,
            'plans' => $plans,
            'salons' => $salons,
            'commission_plan_id' => $commissionPlan?->id,
            'commission_plan' => $commissionPlan,
            'commission_grace_days' => $this->commission->graceDays(),
        ]);
    }

    public function store(Request $request)
    {
        $validated = $request->validate($this->planRules(required: true));

        $validated['created_by'] = $request->user()->id ?? null;
        // Nominating the Commission Model plan is its own deliberate action.
        unset($validated['is_commission_plan']);

        $plan = SubscriptionPlan::create($validated);

        return response()->json([
            'success' => true,
            'message' => 'Plan created successfully',
            'plan' => $plan,
        ]);
    }

    public function update(Request $request, $id)
    {
        $plan = SubscriptionPlan::findOrFail($id);

        $validated = $request->validate($this->planRules(required: false));
        unset($validated['is_commission_plan']);

        // Retiring the plan every commission salon depends on would silently
        // strip their benefits, so it has to be handed over first.
        if ($plan->is_commission_plan && array_key_exists('is_active', $validated) && ! $validated['is_active']) {
            return response()->json([
                'success' => false,
                'message' => 'This is the Commission Model plan. Nominate a different plan before deactivating it.',
            ], 422);
        }

        $plan->update($validated);

        return response()->json([
            'success' => true,
            'message' => 'Plan updated successfully',
            'plan' => $plan->fresh(),
        ]);
    }

    public function destroy($id)
    {
        $plan = SubscriptionPlan::findOrFail($id);

        if ($plan->is_commission_plan) {
            return response()->json([
                'success' => false,
                'message' => 'This is the Commission Model plan. Nominate a different plan before deleting it.',
            ], 422);
        }

        if (SalonSubscription::where('plan_id', $id)->where('status', 'active')->exists()) {
            return response()->json([
                'success' => false,
                'message' => 'Cannot delete plan because active salons are subscribed to it.',
            ], 400);
        }

        $plan->delete();

        return response()->json([
            'success' => true,
            'message' => 'Plan deleted successfully',
        ]);
    }

    /**
     * Nominate the plan whose benefits every Commission Model salon enjoys.
     */
    public function setCommissionPlan(Request $request)
    {
        $request->validate(['plan_id' => 'required|exists:subscription_plans,id']);

        $plan = $this->commission->setPlan(SubscriptionPlan::findOrFail($request->plan_id));

        return response()->json([
            'success' => true,
            'message' => "“{$plan->name}” now carries the benefits for every salon on the Commission Model.",
            'commission_plan' => $plan,
        ]);
    }

    /**
     * Put a salon on a Subscription Plan, or on the Commission Model.
     */
    public function assignToSalon(Request $request, $salonId)
    {
        $salon = Salon::findOrFail($salonId);

        $request->validate([
            'billing_type' => 'required|' . BillingModel::rule(),
            // Only a Subscription Plan needs one picked; the Commission Model
            // has exactly one plan and it is not chosen per salon.
            'plan_id' => 'required_if:billing_type,' . BillingModel::SUBSCRIPTION . '|nullable|exists:subscription_plans,id',
            'commission_percentage' => 'required_if:billing_type,' . BillingModel::COMMISSION . '|nullable|numeric|min:0|max:100',
        ]);

        if (BillingModel::isCommission($request->billing_type)) {
            try {
                $subscription = $this->commission->activate(
                    $salon,
                    (float) $request->commission_percentage,
                    $request->user(),
                    'Assigned from the SuperAdmin dashboard.'
                );
            } catch (\RuntimeException $e) {
                return response()->json(['success' => false, 'message' => $e->getMessage()], 422);
            }

            $this->closePendingRequests($salon->id);

            return response()->json([
                'success' => true,
                'message' => sprintf(
                    '%s is now on the Commission Model at %s%%. The first settlement covers this month and falls due on the 1st.',
                    $salon->name,
                    rtrim(rtrim(number_format((float) $request->commission_percentage, 2), '0'), '.')
                ),
                'subscription' => $subscription,
            ]);
        }

        $plan = SubscriptionPlan::findOrFail($request->plan_id);

        // Leaving the Commission Model closes the rate rather than deleting it —
        // settled payouts still have to be explainable.
        if ($salon->isOnCommissionModel()) {
            $this->commission->deactivate($salon, $request->user());
            $salon->refresh();
        }

        SalonSubscription::where('salon_id', $salon->id)
            ->where('status', 'active')
            ->update([
                'status' => 'cancelled',
                'cancelled_at' => Carbon::now(),
                'cancelled_by' => $request->user()->id,
            ]);

        $subscription = SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'billing_type' => BillingModel::SUBSCRIPTION,
            'commission_percentage' => null,
            'plan_price_snapshot' => $plan->price,
            'start_date' => Carbon::today(),
            'end_date' => Carbon::today()->addDays($plan->validity_days),
            'status' => 'active',
        ]);

        $this->closePendingRequests($salon->id);

        return response()->json([
            'success' => true,
            'message' => "{$salon->name} is now on the {$plan->name} subscription plan.",
            'subscription' => $subscription->load('plan'),
        ]);
    }

    /**
     * Change what a salon is charged on the Commission Model.
     *
     * Refused while the salon has payouts still open — see CommissionService.
     */
    public function setCommissionRate(Request $request, $salonId)
    {
        $salon = Salon::findOrFail($salonId);

        $request->validate([
            'commission_percentage' => 'required|numeric|min:0|max:100',
            'reason' => 'nullable|string|max:255',
        ]);

        try {
            $rate = $this->commission->setRate(
                $salon,
                (float) $request->commission_percentage,
                $request->user(),
                $request->input('reason')
            );
        } catch (\RuntimeException $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
                'unsettled_payouts' => $this->commission->unsettledPayouts($salon->id)
                    ->map(fn ($p) => [
                        'id' => $p->id,
                        'cycle_start_date' => Carbon::parse($p->cycle_start_date)->toDateString(),
                        'cycle_end_date' => Carbon::parse($p->cycle_end_date)->toDateString(),
                        'net_amount' => (float) $p->net_amount,
                        'status' => $p->status,
                    ])->values(),
            ], 422);
        }

        return response()->json([
            'success' => true,
            'message' => sprintf(
                'Commission for %s is now %s%%, charged on everything billed from %s.',
                $salon->name,
                rtrim(rtrim(number_format((float) $request->commission_percentage, 2), '0'), '.'),
                Carbon::parse($rate->effective_from)->format('j M Y')
            ),
            'rate' => $rate,
        ]);
    }

    /** What this salon has been charged, and when it changed. */
    public function commissionHistory($salonId)
    {
        $salon = Salon::findOrFail($salonId);

        return response()->json([
            'success' => true,
            'salon' => ['id' => $salon->id, 'name' => $salon->name],
            'billing_model' => $salon->billingModel(),
            'current_percentage' => $salon->isOnCommissionModel()
                ? (float) ($salon->commission_percentage ?? 0)
                : null,
            'unsettled_payouts' => $this->commission->unsettledPayouts($salon->id)->count(),
            'history' => $salon->commissionRates()->with('setBy:id,name')->get()->map(fn ($rate) => [
                'id' => $rate->id,
                'percentage' => (float) $rate->percentage,
                'effective_from' => $rate->effective_from?->toDateString(),
                'effective_to' => $rate->effective_to?->toDateString(),
                'set_by' => $rate->setBy->name ?? 'System',
                'reason' => $rate->reason,
            ])->values(),
        ]);
    }

    /**
     * Requests waiting on SuperAdmin: paid subscriptions to verify, and salons
     * asking to move onto the Commission Model.
     */
    public function getSubscriptionRequests()
    {
        $requests = SubscriptionPaymentRequest::with(['salon.admin', 'plan'])
            ->where('status', 'pending')
            ->orderBy('created_at', 'desc')
            ->get()
            ->map(function (SubscriptionPaymentRequest $request) {
                $model = BillingModel::normalise($request->billing_type);

                return array_merge($request->toArray(), [
                    'billing_type' => $model,
                    'billing_label' => BillingModel::label($model),
                    // A Commission Model request is not a payment, so there is
                    // no screenshot to check — only a rate to agree.
                    'needs_commission_rate' => BillingModel::isCommission($model),
                ]);
            });

        return response()->json([
            'success' => true,
            'requests' => $requests,
        ]);
    }

    // ------------------------------------------------------------- internals

    private function closePendingRequests(string $salonId): void
    {
        SubscriptionPaymentRequest::where('salon_id', $salonId)
            ->where('status', 'pending')
            ->update(['status' => 'approved']);
    }

    /** @return array<string, string> */
    private function planRules(bool $required): array
    {
        $must = fn (string $rule) => $required ? "required|{$rule}" : $rule;

        return [
            'name' => $must('string|max:50'),
            'price' => $must('numeric'),
            'validity_days' => $must('integer|min:1'),
            'whatsapp_campaign_limit' => $must('integer'),
            'has_customer_segmentation' => 'boolean',
            'has_service_based_targeting' => 'boolean',
            'has_high_value_targeting' => 'boolean',
            'has_advanced_insights' => 'boolean',
            'has_upsell_recommendations' => 'string|in:none,basic,advanced',
            'has_cross_sell_recommendations' => 'string|in:none,basic,advanced',
            'has_priority_visibility' => 'boolean',
            'is_active' => 'boolean',
        ];
    }
}
