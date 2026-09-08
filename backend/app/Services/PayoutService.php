<?php

namespace App\Services;

use App\Models\Appointment;
use App\Models\Salon;
use App\Models\SalonPayout;
use App\Models\User;
use App\Support\BillingModel;
use App\Support\PayoutCycle;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * The settlement between the platform and a salon.
 *
 * Customers pay their advance online — the platform holds that — and the
 * balance in cash at the counter, which the salon keeps. So the only money the
 * platform owes is the advances it collected. Commission, however, is charged
 * on everything the salon billed in the cycle, not just the part passing
 * through the platform, which is why both figures are recorded.
 *
 *     net = advances held − commission − refunds + coins settled
 *
 * How often that happens depends on how the salon pays:
 *
 *  - Subscription Plan salons have already paid for their access, so the only
 *    thing to hand back is advances. That runs weekly; there is no reason to
 *    sit on money that is already theirs.
 *  - Commission Model salons owe a percentage of a month's trading, settled on
 *    the 1st for the month just finished. Settling that weekly would be billing
 *    one month in four pieces for no gain.
 */
class PayoutService
{
    /** Appointments that count as earned revenue for a cycle. */
    public const SETTLED_STATUSES = ['completed'];

    public const STATUS_PENDING = 'pending';
    public const STATUS_APPROVED = 'approved';
    public const STATUS_DISTRIBUTED = 'distributed';

    public function __construct(private CommissionService $commission)
    {
    }

    /**
     * Build or refresh one salon's payout for one cycle.
     *
     * Safe to re-run while the payout is still pending — a cycle recalculated
     * after a late completion should pick it up. Once distributed the record is
     * frozen, because the money has already moved and the salon has been told
     * what it was charged.
     */
    public function calculate(string $salonId, Carbon $start, Carbon $end, ?string $cycleType = null): SalonPayout
    {
        $salon = Salon::find($salonId);
        $billingModel = $salon?->billingModel() ?? BillingModel::SUBSCRIPTION;
        $cycleType ??= PayoutCycle::forBillingModel($billingModel);

        $existing = SalonPayout::where('salon_id', $salonId)
            ->where('cycle_type', $cycleType)
            ->whereDate('cycle_start_date', $start->toDateString())
            ->first();

        if ($existing && $existing->status === self::STATUS_DISTRIBUTED) {
            return $existing;
        }

        $appointments = Appointment::where('salon_id', $salonId)
            ->whereIn('status', self::SETTLED_STATUSES)
            ->whereBetween('appointment_date', [$start->toDateString(), $end->toDateString()])
            ->get(['id', 'total_amount', 'final_billed_amount', 'advance_amount']);

        // What the salon billed customers, which is what commission is charged on.
        $revenue = $appointments->sum(
            fn (Appointment $a) => (float) ($a->final_billed_amount ?? $a->total_amount)
        );

        // What the platform is actually holding on the salon's behalf.
        $advancesHeld = (float) $appointments->sum('advance_amount');

        // A Subscription Plan salon has already paid; nothing is deducted.
        // A rate change is blocked until every payout is settled, so the rate
        // standing now is the rate this cycle was always going to be charged.
        $rate = BillingModel::isCommission($billingModel)
            ? $this->commission->currentRate($salon)
            : 0.0;

        $commission = round($revenue * $rate / 100, 2);
        $refunds = $this->refundsInCycle($salonId, $start, $end);

        // Coins already settled against this cycle stay put — they were spent
        // deliberately and give the salon back part of the commission.
        $walletRedeemed = (float) ($existing->wallet_redeemed_amount ?? 0);

        $payout = SalonPayout::updateOrCreate(
            [
                'salon_id' => $salonId,
                'cycle_type' => $cycleType,
                'cycle_start_date' => $start->toDateString(),
            ],
            [
                'cycle_end_date' => $end->toDateString(),
                'gross_amount' => round($advancesHeld, 2),
                'appointment_revenue' => round($revenue, 2),
                'appointments_count' => $appointments->count(),
                'billing_type' => $billingModel,
                'commission_percentage_snapshot' => $rate,
                'commission_deducted' => $commission,
                'refund_adjustment' => $refunds,
                'wallet_redeemed_amount' => $walletRedeemed,
                'net_amount' => $this->net($advancesHeld, $commission, $refunds, $walletRedeemed),
                'status' => $existing->status ?? self::STATUS_PENDING,
                'calculated_at' => now(),
            ]
        );

        return $payout->fresh();
    }

    /**
     * The weekly run: every Subscription Plan salon that traded in the week.
     *
     * @return array{cycle_type: string, start: string, end: string, payouts: int}
     */
    public function generateWeekly(Carbon $inWeek): array
    {
        [$start, $end] = PayoutCycle::bounds(PayoutCycle::WEEKLY, $inWeek);

        return $this->runCycle(PayoutCycle::WEEKLY, $start, $end, BillingModel::SUBSCRIPTION);
    }

    /**
     * The monthly run: every Commission Model salon that traded in the month.
     *
     * @return array{cycle_type: string, start: string, end: string, payouts: int}
     */
    public function generateMonthly(Carbon $inMonth): array
    {
        [$start, $end] = PayoutCycle::bounds(PayoutCycle::MONTHLY, $inMonth);

        return $this->runCycle(PayoutCycle::MONTHLY, $start, $end, BillingModel::COMMISSION);
    }

    /**
     * Both runs for whatever has just closed.
     *
     * The monthly leg only fires on the 1st, which is when a month is settled.
     * Calling this on any other day is a no-op for commission salons rather
     * than an error, so it can sit on a daily schedule.
     *
     * @return array{weekly: array, monthly: ?array}
     */
    public function generateDue(?Carbon $on = null, bool $force = false): array
    {
        $today = ($on ?? Carbon::today())->copy();

        [$weekStart] = PayoutCycle::previousBounds(PayoutCycle::WEEKLY, $today);
        $weekly = $this->generateWeekly($weekStart);

        $monthly = null;

        if ($force || $today->day === 1) {
            [$monthStart] = PayoutCycle::previousBounds(PayoutCycle::MONTHLY, $today);
            $monthly = $this->generateMonthly($monthStart);
        }

        return ['weekly' => $weekly, 'monthly' => $monthly];
    }

    /**
     * Sign off the figures. Distribution stays a separate step so the money
     * moving is always a deliberate second action.
     */
    public function approve(SalonPayout $payout, User $actor): SalonPayout
    {
        if ($payout->status === self::STATUS_DISTRIBUTED) {
            throw new \RuntimeException('This payout has already been distributed.');
        }

        $payout->forceFill([
            'status' => self::STATUS_APPROVED,
            'approved_by' => $actor->id,
            'approved_at' => now(),
        ])->save();

        return $payout->fresh();
    }

    /**
     * Record that the net amount has been paid out.
     *
     * The commission comes off here, in the same cycle, before the record is
     * closed — the salon receives the net and the deduction stays on the record
     * for both sides to refer to. Settling a Commission Model month also buys
     * the salon the month that follows it.
     */
    public function markDistributed(SalonPayout $payout, User $actor, ?string $reference, ?string $notes = null): SalonPayout
    {
        if ($payout->status === self::STATUS_DISTRIBUTED) {
            throw new \RuntimeException('This payout has already been distributed.');
        }

        return DB::transaction(function () use ($payout, $actor, $reference, $notes) {
            $payout->forceFill([
                // Recomputed one last time so a late change cannot leave the
                // distributed figure disagreeing with its own components.
                'net_amount' => $this->net(
                    (float) $payout->gross_amount,
                    (float) $payout->commission_deducted,
                    (float) $payout->refund_adjustment,
                    (float) $payout->wallet_redeemed_amount
                ),
                'status' => self::STATUS_DISTRIBUTED,
                'distributed_by' => $actor->id,
                'distributed_at' => now(),
                'distribution_reference' => $reference,
                'notes' => $notes ?? $payout->notes,
            ])->save();

            $this->commission->extendAccessAfterSettlement($payout->fresh());

            return $payout->fresh();
        });
    }

    /**
     * The salon's own view of a payout: the same numbers SuperAdmin sees, with
     * the commission deduction spelled out.
     */
    public function present(SalonPayout $payout): array
    {
        $start = Carbon::parse($payout->cycle_start_date);
        $end = Carbon::parse($payout->cycle_end_date);
        $cycleType = $payout->cycle_type ?? PayoutCycle::WEEKLY;

        return [
            'id' => $payout->id,
            'salon_id' => $payout->salon_id,
            'salon_name' => $payout->salon->name ?? null,
            'cycle_type' => $cycleType,
            'cycle_label' => PayoutCycle::label($cycleType, $start, $end),
            'cycle_start_date' => $start->toDateString(),
            'cycle_end_date' => $end->toDateString(),
            'appointments_count' => (int) $payout->appointments_count,
            'appointment_revenue' => (float) $payout->appointment_revenue,
            'gross_amount' => (float) $payout->gross_amount,
            'billing_type' => BillingModel::normalise($payout->billing_type),
            'billing_label' => BillingModel::label($payout->billing_type),
            'commission_percentage' => (float) $payout->commission_percentage_snapshot,
            'commission_deducted' => (float) $payout->commission_deducted,
            'refund_adjustment' => (float) $payout->refund_adjustment,
            'wallet_redeemed_amount' => (float) $payout->wallet_redeemed_amount,
            'net_amount' => (float) $payout->net_amount,
            'status' => $payout->status,
            'approved_at' => $payout->approved_at,
            'distributed_at' => $payout->distributed_at,
            'distribution_reference' => $payout->distribution_reference,
            'notes' => $payout->notes,
        ];
    }

    // ------------------------------------------------------------- internals

    /**
     * Build the cycle for every salon on $billingModel that traded in it.
     *
     * @return array{cycle_type: string, start: string, end: string, payouts: int}
     */
    private function runCycle(string $cycleType, Carbon $start, Carbon $end, string $billingModel): array
    {
        $tradedIds = Appointment::whereIn('status', self::SETTLED_STATUSES)
            ->whereBetween('appointment_date', [$start->toDateString(), $end->toDateString()])
            ->distinct()
            ->pluck('salon_id');

        // Only the salons settling on this rhythm. A salon that switched models
        // mid-cycle settles on whichever one it is on now, so a cycle is never
        // built twice for the same money.
        $salonIds = Salon::whereIn('id', $tradedIds)
            ->where('commission_opt_in', BillingModel::isCommission($billingModel))
            ->pluck('id');

        foreach ($salonIds as $salonId) {
            $this->calculate($salonId, $start, $end, $cycleType);
        }

        return [
            'cycle_type' => $cycleType,
            'start' => $start->toDateString(),
            'end' => $end->toDateString(),
            'payouts' => $salonIds->count(),
        ];
    }

    private function net(float $advancesHeld, float $commission, float $refunds, float $walletRedeemed): float
    {
        // Coins settled against commission give that much back to the salon.
        return round($advancesHeld - $commission - $refunds + $walletRedeemed, 2);
    }

    /**
     * Refunds raised in the cycle come off what the platform hands over.
     */
    private function refundsInCycle(string $salonId, Carbon $start, Carbon $end): float
    {
        return round((float) DB::table('payment_refunds')
            ->join('appointments', 'appointments.id', '=', 'payment_refunds.appointment_id')
            ->where('appointments.salon_id', $salonId)
            ->whereBetween('payment_refunds.created_at', [$start->copy()->startOfDay(), $end->copy()->endOfDay()])
            ->sum('payment_refunds.amount'), 2);
    }
}
