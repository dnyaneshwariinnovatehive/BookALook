<?php

namespace App\Services;

use App\Models\PlatformPolicySetting;
use App\Models\Salon;
use App\Models\SalonCommissionRate;
use App\Models\SalonPayout;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Support\BillingModel;
use App\Support\PayoutCycle;
use Carbon\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * The Commission Model: postpaid trading, settled monthly.
 *
 * A salon on this arrangement pays nothing up front. It enjoys the benefits of
 * one nominated plan — the same one for every commission salon, so two salons
 * paying the same way get the same thing — and owes SuperAdmin a percentage of
 * what it billed, settled on the 1st for the month just finished.
 *
 * Access is granted a month at a time and extended when a month is settled. A
 * salon that never settles therefore stops trading on its own, without anyone
 * having to remember to switch it off.
 *
 * The rate can only be changed once every payout for that salon has been
 * distributed. Otherwise a pending cycle could be recalculated at the new rate
 * after the salon had already been told what it owed.
 */
class CommissionService
{
    /**
     * Days after a month ends before an unsettled commission salon loses access.
     *
     * The month's payout is generated on the 1st and someone has to actually
     * look at it; locking the salon out that morning would punish it for the
     * platform's own admin queue.
     */
    public const GRACE_DAYS_KEY = 'commission_settlement_grace_days';

    /** ------------------------------------------------------------- the plan */

    public function plan(): ?SubscriptionPlan
    {
        return SubscriptionPlan::commissionPlan();
    }

    /**
     * Nominate the plan whose benefits commission salons get.
     *
     * Exactly one plan carries the flag, so nominating a new one stands the old
     * one down. Salons already trading are moved onto it, because the promise
     * was "the commission plan", not "the plan that was the commission plan
     * when you signed up".
     */
    public function setPlan(SubscriptionPlan $plan): SubscriptionPlan
    {
        return DB::transaction(function () use ($plan) {
            SubscriptionPlan::where('is_commission_plan', true)
                ->where('id', '!=', $plan->id)
                ->update(['is_commission_plan' => false]);

            $plan->forceFill(['is_commission_plan' => true, 'is_active' => true])->save();

            SalonSubscription::where('billing_type', BillingModel::COMMISSION)
                ->where('status', 'active')
                ->update(['plan_id' => $plan->id, 'plan_price_snapshot' => 0]);

            return $plan->fresh();
        });
    }

    /** ------------------------------------------------------------ the rate */

    /**
     * The rate a salon is on right now.
     */
    public function currentRate(Salon $salon): float
    {
        return (float) ($salon->commission_percentage ?? 0);
    }

    /**
     * The rate that was in force on a date, for explaining an old payout.
     */
    public function rateOn(string $salonId, Carbon $date): float
    {
        $rate = SalonCommissionRate::where('salon_id', $salonId)
            ->whereDate('effective_from', '<=', $date->toDateString())
            ->where(fn ($q) => $q->whereNull('effective_to')
                ->orWhereDate('effective_to', '>=', $date->toDateString()))
            ->orderByDesc('effective_from')
            ->first();

        return (float) ($rate->percentage ?? 0);
    }

    /**
     * Payouts standing between SuperAdmin and a rate change.
     *
     * @return Collection<int, SalonPayout>
     */
    public function unsettledPayouts(string $salonId): Collection
    {
        return SalonPayout::where('salon_id', $salonId)
            ->unsettled()
            ->orderBy('cycle_start_date')
            ->get();
    }

    /**
     * Change what a salon is charged, from now on.
     *
     * Refused while any payout is still open. Settling first is what makes the
     * boundary honest: everything the salon has been billed for was billed at
     * the old rate, and everything from here is billed at the new one. Without
     * that, a pending cycle would silently be recalculated at the new rate.
     *
     * @throws \RuntimeException when the salon has payouts still to settle
     */
    public function setRate(Salon $salon, float $percentage, User $actor, ?string $reason = null): SalonCommissionRate
    {
        if (! $salon->isOnCommissionModel()) {
            throw new \RuntimeException(
                'This salon is on a Subscription Plan. Move it to the Commission Model before setting a rate.'
            );
        }

        $blocking = $this->unsettledPayouts($salon->id);

        if ($blocking->isNotEmpty()) {
            throw new \RuntimeException(sprintf(
                'Settle this salon’s %d open payout%s before changing the rate. %s',
                $blocking->count(),
                $blocking->count() === 1 ? '' : 's',
                $blocking
                    ->map(fn (SalonPayout $p) => Carbon::parse($p->cycle_start_date)->format('j M Y') . " ({$p->status})")
                    ->join(', ')
            ));
        }

        return $this->writeRate($salon, $percentage, $actor, $reason);
    }

    /** ------------------------------------------------------- joining/leaving */

    /**
     * Put a salon onto the Commission Model.
     *
     * The subscription row still exists — it is what the rest of the platform
     * reads to decide the salon is trading — but it is not something the salon
     * bought, so it is priced at zero and carries the commission plan.
     */
    public function activate(Salon $salon, float $percentage, User $actor, ?string $reason = null): SalonSubscription
    {
        $plan = $this->plan();

        if (! $plan) {
            throw new \RuntimeException(
                'No plan has been nominated for the Commission Model yet. Set one before moving salons onto it.'
            );
        }

        return DB::transaction(function () use ($salon, $percentage, $actor, $reason, $plan) {
            SalonSubscription::where('salon_id', $salon->id)
                ->where('status', 'active')
                ->update(['status' => 'cancelled', 'cancelled_at' => now(), 'cancelled_by' => $actor->id]);

            $salon->forceFill(['commission_opt_in' => true])->save();

            $this->writeRate($salon, $percentage, $actor, $reason ?? 'Moved to the Commission Model.');

            $subscription = SalonSubscription::create([
                'salon_id' => $salon->id,
                'plan_id' => $plan->id,
                'billing_type' => BillingModel::COMMISSION,
                'commission_percentage' => $percentage,
                // Nothing was paid for it, so there is no price to snapshot.
                'plan_price_snapshot' => 0,
                'start_date' => Carbon::today(),
                // Nothing has been settled yet, so the salon is covered for the
                // month it is joining in and no further. Passing today would
                // read as "this month is already paid for" and hand it a free
                // extra month.
                'end_date' => $this->accessEndFrom(Carbon::today()->subMonthNoOverflow()->startOfMonth()),
                'status' => 'active',
            ]);

            return $subscription->fresh('plan');
        });
    }

    /**
     * Take a salon off the Commission Model and back onto a plan it buys.
     *
     * The rate is closed rather than deleted — payouts already settled against
     * it still have to be explainable.
     */
    public function deactivate(Salon $salon, User $actor): void
    {
        DB::transaction(function () use ($salon, $actor) {
            SalonCommissionRate::where('salon_id', $salon->id)
                ->current()
                ->update(['effective_to' => Carbon::today()]);

            SalonSubscription::where('salon_id', $salon->id)
                ->where('status', 'active')
                ->where('billing_type', BillingModel::COMMISSION)
                ->update(['status' => 'cancelled', 'cancelled_at' => now(), 'cancelled_by' => $actor->id]);

            $salon->forceFill([
                'commission_opt_in' => false,
                'commission_percentage' => null,
                'commission_rate_effective_from' => null,
            ])->save();
        });
    }

    /** ---------------------------------------------------------- the window */

    /**
     * How long a commission salon may trade, given the last month it settled.
     *
     * A settled month buys the month that follows it, plus the grace the
     * platform allows for getting the next settlement out.
     */
    public function accessEndFrom(Carbon $lastSettledCycleStart): Carbon
    {
        return $lastSettledCycleStart->copy()
            ->addMonthNoOverflow()
            ->endOfMonth()
            ->startOfDay()
            ->addDays($this->graceDays());
    }

    /**
     * Extend a commission salon's access because it has settled a month.
     *
     * Only ever pushes the date outwards — settling an old cycle late must not
     * shorten a window a later cycle has already earned.
     */
    public function extendAccessAfterSettlement(SalonPayout $payout): ?SalonSubscription
    {
        if (! BillingModel::isCommission($payout->billing_type)
            || $payout->cycle_type !== PayoutCycle::MONTHLY) {
            return null;
        }

        $subscription = SalonSubscription::where('salon_id', $payout->salon_id)
            ->where('billing_type', BillingModel::COMMISSION)
            ->orderByDesc('start_date')
            ->first();

        if (! $subscription) {
            return null;
        }

        $earned = $this->accessEndFrom(Carbon::parse($payout->cycle_start_date));

        if (Carbon::parse($subscription->end_date)->gte($earned)) {
            return $subscription;
        }

        $subscription->forceFill([
            'end_date' => $earned,
            // Settling revives a salon that had been locked out for not paying.
            'status' => 'active',
        ])->save();

        return $subscription->fresh();
    }

    public function graceDays(): int
    {
        return (int) PlatformPolicySetting::value(self::GRACE_DAYS_KEY);
    }

    /** ------------------------------------------------------------ internals */

    /**
     * Close the running rate and open a new one from today.
     */
    private function writeRate(Salon $salon, float $percentage, User $actor, ?string $reason): SalonCommissionRate
    {
        return DB::transaction(function () use ($salon, $percentage, $actor, $reason) {
            $today = Carbon::today();

            SalonCommissionRate::where('salon_id', $salon->id)
                ->current()
                ->update(['effective_to' => $today]);

            $salon->forceFill([
                'commission_percentage' => $percentage,
                'commission_rate_effective_from' => $today,
            ])->save();

            // The live subscription carries the same figure so anything reading
            // the subscription alone still sees the truth.
            SalonSubscription::where('salon_id', $salon->id)
                ->where('status', 'active')
                ->where('billing_type', BillingModel::COMMISSION)
                ->update(['commission_percentage' => $percentage]);

            return SalonCommissionRate::create([
                'salon_id' => $salon->id,
                'percentage' => $percentage,
                'effective_from' => $today,
                'effective_to' => null,
                'set_by' => $actor->id,
                'reason' => $reason,
            ]);
        });
    }
}
