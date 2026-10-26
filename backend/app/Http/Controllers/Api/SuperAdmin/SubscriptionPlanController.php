<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPaymentRequest;
use App\Models\SubscriptionPlan;
use App\Services\AuditLogger;
use App\Services\CommissionService;
use App\Services\Notifications\NotificationService;
use App\Services\WalletService;
use App\Support\BillingModel;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Log;

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
    public function __construct(
        private CommissionService $commission,
        private NotificationService $notifications
    ) {
    }

    /**
     * Plans, the nominated Commission Model plan, and where every salon stands.
     */
    public function index()
    {
        $plans = SubscriptionPlan::orderByDesc('is_commission_plan')->orderBy('price')->get();

        // Payment totals per salon in one query each, not one per row.
        $paidBySalon = SubscriptionPaymentRequest::where('status', 'approved')
            ->groupBy('salon_id')
            ->selectRaw('salon_id, SUM(COALESCE(amount_payable_inr, 0)) as total, COUNT(*) as payments, MAX(updated_at) as last_paid_at')
            ->get()
            ->keyBy('salon_id');
        $pendingBySalon = SubscriptionPaymentRequest::where('status', 'pending')
            ->groupBy('salon_id')
            ->selectRaw('salon_id, COUNT(*) as pending')
            ->pluck('pending', 'salon_id');

        $salons = Salon::with(['currentSubscription.plan', 'admin', 'city:id,name'])->get()->map(function (Salon $salon) use ($paidBySalon, $pendingBySalon) {
            $model = $salon->billingModel();
            $subscription = $salon->currentSubscription;
            $paid = $paidBySalon->get($salon->id);

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
                // For the dashboard tables: who to call, where, and how the
                // money has gone so far.
                'owner_phone' => $salon->admin?->phone,
                'city' => $salon->city?->name,
                'salon_status' => $salon->status,
                'plan_started' => $subscription?->start_date?->format('Y-m-d'),
                'plan_price' => $subscription ? (float) ($subscription->plan_price_snapshot ?? $subscription->plan?->price ?? 0) : null,
                'plan_validity_days' => $subscription?->plan?->validity_days,
                'lifetime_paid' => round((float) ($paid->total ?? 0), 2),
                'payments_count' => (int) ($paid->payments ?? 0),
                'last_paid_at' => $paid?->last_paid_at ? \Illuminate\Support\Carbon::parse($paid->last_paid_at)->toDateString() : null,
                'pending_requests' => (int) ($pendingBySalon[$salon->id] ?? 0),
                'joined_at' => $salon->created_at?->toDateString(),
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

        AuditLogger::record(
            action: AuditLog::PLAN_CREATED,
            entity: $plan,
            label: $plan->name,
            after: ['price' => (float) $plan->price, 'validity_days' => (int) $plan->validity_days],
        );

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

        $before = $plan->only(array_keys($validated));
        $plan->update($validated);

        AuditLogger::record(
            action: AuditLog::PLAN_UPDATED,
            entity: $plan,
            label: $plan->name,
            before: $before,
            after: $plan->fresh()->only(array_keys($validated)),
        );

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

        // Only a subscription still running counts. A short plan's rows can
        // keep saying "active" after their end date, because nothing flips them
        // until the salon next renews, and that alone must not pin the plan.
        $running = SalonSubscription::where('plan_id', $id)
            ->where('status', 'active')
            ->whereDate('end_date', '>=', now()->toDateString())
            ->exists();

        if ($running) {
            return response()->json([
                'success' => false,
                'message' => 'Cannot delete plan because active salons are subscribed to it.',
            ], 400);
        }

        // Approving one of these after the plan is gone would hand a salon a
        // subscription to a plan nobody can see any more.
        if (SubscriptionPaymentRequest::where('subscription_plan_id', $id)->where('status', 'pending')->exists()) {
            return response()->json([
                'success' => false,
                'message' => 'A salon has a payment for this plan waiting to be verified. Approve or reject it first.',
            ], 400);
        }

        AuditLogger::record(
            action: AuditLog::PLAN_DELETED,
            entity: $plan,
            label: $plan->name,
            before: ['price' => (float) $plan->price, 'validity_days' => (int) $plan->validity_days],
        );

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

        // The owner transferred the balance after coins, so the coins have to
        // come out now that the plan exists. Done before the request is closed,
        // while it still says how many were promised.
        $coinsSpent = $this->redeemCoinsPromisedOn($salon, $plan, $subscription, $request->user());

        AuditLogger::record(
            action: AuditLog::SUBSCRIPTION_ASSIGNED,
            entity: $salon,
            label: $salon->name,
            after: ['plan' => $plan->name, 'price' => (float) $plan->price],
            metadata: ['coins_applied' => $coinsSpent],
        );

        $this->closePendingRequests($salon->id);

        // Most renewals land here rather than through the owner's own button:
        // the owner uploads a transfer and SuperAdmin is the one who turns it
        // into a live plan. The collaborator has been told this salon is about
        // to go dark, so they are owed the confirmation too.
        $this->notifications->assignedSalonRenewed($salon, $subscription->fresh('plan'));

        return response()->json([
            'success' => true,
            'message' => "{$salon->name} is now on the {$plan->name} subscription plan."
                . ($coinsSpent > 0 ? " {$coinsSpent} coins were applied." : ''),
            'coins_redeemed' => $coinsSpent,
            'subscription' => $subscription->load('plan'),
        ]);
    }

    /**
     * Spend the coins the salon put against its pending request.
     *
     * The request only ever held the intent — this is where the coins actually
     * leave the wallet. Recomputed against the balance as it stands rather than
     * trusting the recorded figure, because a salon that spent coins elsewhere
     * in the meantime must not be able to overdraw. A salon that no longer has
     * them simply gets less off; it never fails the approval, because the
     * subscription is already real and blocking it would leave a salon that has
     * paid stuck offline.
     */
    private function redeemCoinsPromisedOn(
        Salon $salon,
        SubscriptionPlan $plan,
        SalonSubscription $subscription,
        $actor
    ): int {
        $pending = SubscriptionPaymentRequest::where('salon_id', $salon->id)
            ->where('status', 'pending')
            ->where('subscription_plan_id', $plan->id)
            ->latest('created_at')
            ->first();

        $promised = (int) ($pending->coins_to_redeem ?? 0);

        if ($promised < 1) {
            return 0;
        }

        $wallet = app(WalletService::class);
        $coins = min($promised, $wallet->quote($salon->id, (float) $plan->price)['coins']);

        if ($coins < 1) {
            return 0;
        }

        try {
            $wallet->redeemForSubscription(
                $salon->id,
                $coins,
                (float) $plan->price,
                $actor,
                $subscription,
                "Applied to {$plan->name}"
            );
        } catch (\RuntimeException $e) {
            Log::warning('Could not apply coins to an approved subscription', [
                'salon_id' => $salon->id,
                'promised' => $promised,
                'error' => $e->getMessage(),
            ]);

            return 0;
        }

        return $coins;
    }

    /**
     * Change what a salon is charged on the Commission Model.
     *
     * Refused while the salon has payouts still open — see CommissionService.
     */
    public function setCommissionRate(Request $request, $salonId)
    {
        $salon = Salon::findOrFail($salonId);
        $previousRate = $salon->commission_percentage;

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

        // What a salon is charged, changed by hand. If any single entry ever
        // needs defending months later, it is this one.
        AuditLogger::record(
            action: AuditLog::COMMISSION_RATE_CHANGED,
            entity: $salon,
            label: $salon->name,
            before: ['commission_percentage' => $previousRate === null ? null : (float) $previousRate],
            after: ['commission_percentage' => (float) $request->commission_percentage],
            metadata: [
                'reason' => $request->input('reason'),
                'effective_from' => Carbon::parse($rate->effective_from)->toDateString(),
            ],
        );

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
     * All subscription plans this salon has ever been on (active, expired, cancelled).
     */
    public function subscriptionHistory($salonId)
    {
        $salon = Salon::with(['admin'])->findOrFail($salonId);

        // Keep expired plans accurate before listing
        SalonSubscription::where('salon_id', $salon->id)
            ->where('status', 'active')
            ->whereDate('end_date', '<', Carbon::today())
            ->update(['status' => 'expired']);

        $currentSubscription = $salon->currentSubscription()->with('plan')->first();

        $history = SalonSubscription::with('plan')
            ->where('salon_id', $salon->id)
            ->orderByDesc('created_at')
            ->get()
            ->map(function (SalonSubscription $sub) {
                $isCommission = BillingModel::isCommission($sub->billing_type);

                return [
                    'id' => $sub->id,
                    'plan_id' => $sub->plan_id,
                    'plan_name' => $sub->plan?->name ?? ($isCommission ? 'Commission Plan' : 'Custom Plan'),
                    'billing_type' => $sub->billing_type ?? BillingModel::SUBSCRIPTION,
                    'billing_label' => BillingModel::label($sub->billing_type ?? BillingModel::SUBSCRIPTION),
                    'price' => (float) ($sub->plan_price_snapshot ?? $sub->plan?->price ?? 0),
                    'commission_percentage' => $sub->commission_percentage !== null ? (float) $sub->commission_percentage : null,
                    'validity_days' => $sub->plan?->validity_days,
                    'whatsapp_campaign_limit' => $sub->plan?->whatsapp_campaign_limit,
                    'start_date' => $sub->start_date?->toDateString(),
                    'end_date' => $sub->end_date?->toDateString(),
                    'status' => $sub->status,
                    'auto_renew' => (bool) $sub->auto_renew,
                    'cancelled_at' => $sub->cancelled_at?->toDateTimeString(),
                    'created_at' => $sub->created_at?->toDateTimeString(),
                ];
            })->values();

        $paymentRequests = SubscriptionPaymentRequest::with('plan')
            ->where('salon_id', $salon->id)
            ->orderByDesc('created_at')
            ->get()
            ->map(function (SubscriptionPaymentRequest $pr) {
                $model = BillingModel::normalise($pr->billing_type);

                return [
                    'id' => $pr->id,
                    'plan_name' => $pr->plan?->name ?? '—',
                    'billing_type' => $model,
                    'billing_label' => BillingModel::label($model),
                    'amount_payable_inr' => $pr->amount_payable_inr !== null ? (float) $pr->amount_payable_inr : null,
                    'coins_to_redeem' => (int) $pr->coins_to_redeem,
                    'transaction_id' => $pr->transaction_id,
                    'note' => $pr->note,
                    'status' => $pr->status,
                    'screenshot_url' => $pr->screenshot_url,
                    'created_at' => $pr->created_at?->toDateTimeString(),
                ];
            })->values();

        return response()->json([
            'success' => true,
            'salon' => [
                'id' => $salon->id,
                'name' => $salon->name,
                'owner' => $salon->admin->name ?? 'Unknown',
                'billing_model' => $salon->billingModel(),
                'billing_label' => BillingModel::label($salon->billingModel()),
            ],
            'current_subscription' => $currentSubscription ? [
                'id' => $currentSubscription->id,
                'plan_name' => $currentSubscription->plan?->name ?? 'Custom Plan',
                'price' => (float) ($currentSubscription->plan_price_snapshot ?? $currentSubscription->plan?->price ?? 0),
                'start_date' => $currentSubscription->start_date?->toDateString(),
                'end_date' => $currentSubscription->end_date?->toDateString(),
                'status' => $currentSubscription->status,
            ] : null,
            'subscriptions' => $history,
            'payment_requests' => $paymentRequests,
        ]);
    }

    /**
     * Requests made by salons: paid subscriptions to verify, and salons asking
     * to move onto the Commission Model.
     *
     * Defaults to pending, which is the queue the dashboard is built around. A
     * `status` of `all` widens it to everything ever raised, because a request
     * that has been approved or rejected is the only record that a salon paid —
     * and the transaction id and note the owner typed with it are the reason
     * those are kept at all.
     */
    public function getSubscriptionRequests(Request $request)
    {
        $status = (string) $request->input('status', 'pending');

        $query = SubscriptionPaymentRequest::with(['salon.admin', 'plan'])
            ->orderBy('created_at', 'desc');

        if ($status !== 'all') {
            $query->where('status', $status);
        }

        $requests = $query
            ->limit(200)
            ->get()
            ->map(function (SubscriptionPaymentRequest $request) {
                $model = BillingModel::normalise($request->billing_type);

                return array_merge($request->toArray(), [
                    'billing_type' => $model,
                    'billing_label' => BillingModel::label($model),
                    // A Commission Model request is not a payment, so there is
                    // no screenshot to check — only a rate to agree.
                    'needs_commission_rate' => BillingModel::isCommission($model),
                    // A blank from the app is stored as null, so a screen that
                    // checks this never has to tell "" from "not provided".
                    'transaction_id' => $request->transaction_id ?: null,
                    'note' => $request->note ?: null,
                ]);
            });

        return response()->json([
            'success' => true,
            'status' => $status,
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
            // Salons no longer send WhatsApp marketing, so the campaign and
            // targeting columns are left alone; they are not part of a plan.
            // Plans differ only in insights: Growth's analytics and the
            // basic-or-full level of upsell and cross-sell suggestions.
            'has_advanced_insights' => 'boolean',
            'has_upsell_recommendations' => 'string|in:basic,advanced',
            'has_cross_sell_recommendations' => 'string|in:basic,advanced',
            'is_active' => 'boolean',
        ];
    }
}
