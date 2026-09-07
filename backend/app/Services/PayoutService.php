<?php

namespace App\Services;

use App\Models\Appointment;
use App\Models\Salon;
use App\Models\SalonPayout;
use App\Models\SalonSubscription;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * The weekly settlement between the platform and a salon.
 *
 * Customers pay their advance online — the platform holds that — and the
 * balance in cash at the counter, which the salon keeps. So the only money the
 * platform owes is the advances it collected. Commission, however, is charged
 * on everything the salon billed that week, not just the part passing through
 * the platform, which is why both figures are recorded.
 *
 *     net = advances held − commission − refunds + coins settled
 */
class PayoutService
{
    /** Appointments that count as earned revenue for a cycle. */
    public const SETTLED_STATUSES = ['completed'];

    public const STATUS_PENDING = 'pending';
    public const STATUS_APPROVED = 'approved';
    public const STATUS_DISTRIBUTED = 'distributed';

    /**
     * Build or refresh the payout for one salon and one week.
     *
     * Safe to re-run while the payout is still pending — a cycle that is
     * recalculated after a late completion should pick it up. Once distributed
     * the record is frozen, because the money has already moved.
     */
    public function calculate(string $salonId, Carbon $weekStart, Carbon $weekEnd): SalonPayout
    {
        $existing = SalonPayout::where('salon_id', $salonId)
            ->whereDate('cycle_week_start_date', $weekStart->toDateString())
            ->first();

        if ($existing && $existing->status === self::STATUS_DISTRIBUTED) {
            return $existing;
        }

        $appointments = Appointment::where('salon_id', $salonId)
            ->whereIn('status', self::SETTLED_STATUSES)
            ->whereBetween('appointment_date', [$weekStart->toDateString(), $weekEnd->toDateString()])
            ->get(['id', 'total_amount', 'final_billed_amount', 'advance_amount']);

        // What the salon billed customers, which is what commission is charged on.
        $revenue = $appointments->sum(
            fn (Appointment $a) => (float) ($a->final_billed_amount ?? $a->total_amount)
        );

        // What the platform is actually holding on the salon's behalf.
        $advancesHeld = (float) $appointments->sum('advance_amount');

        $plan = $this->activePlan($salonId);
        $isCommission = $plan && $plan->billing_type === 'commission';
        $rate = $isCommission ? (float) ($plan->commission_percentage ?? 0) : 0.0;
        $commission = round($revenue * $rate / 100, 2);

        $refunds = $this->refundsInCycle($salonId, $weekStart, $weekEnd);

        // Coins already settled against this cycle stay put — they were spent
        // deliberately and give the salon back part of the commission.
        $walletRedeemed = (float) ($existing->wallet_redeemed_amount ?? 0);

        $payout = SalonPayout::updateOrCreate(
            [
                'salon_id' => $salonId,
                'cycle_week_start_date' => $weekStart->toDateString(),
            ],
            [
                'cycle_week_end_date' => $weekEnd->toDateString(),
                'gross_amount' => round($advancesHeld, 2),
                'appointment_revenue' => round($revenue, 2),
                'appointments_count' => $appointments->count(),
                'billing_type' => $plan->billing_type ?? 'flat',
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
     * Build the week for every salon that traded in it.
     *
     * @return array{week_start: string, week_end: string, payouts: int}
     */
    public function generateForWeek(Carbon $weekStart): array
    {
        $start = $weekStart->copy()->startOfWeek();
        $end = $start->copy()->endOfWeek();

        $salonIds = Appointment::whereIn('status', self::SETTLED_STATUSES)
            ->whereBetween('appointment_date', [$start->toDateString(), $end->toDateString()])
            ->distinct()
            ->pluck('salon_id');

        foreach ($salonIds as $salonId) {
            $this->calculate($salonId, $start, $end);
        }

        return [
            'week_start' => $start->toDateString(),
            'week_end' => $end->toDateString(),
            'payouts' => $salonIds->count(),
        ];
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
     * for both sides to refer to.
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

            return $payout->fresh();
        });
    }

    /**
     * The salon's own view of a payout: the same numbers SuperAdmin sees, with
     * the commission deduction spelled out.
     */
    public function present(SalonPayout $payout): array
    {
        return [
            'id' => $payout->id,
            'salon_id' => $payout->salon_id,
            'salon_name' => $payout->salon->name ?? null,
            'cycle_week_start_date' => Carbon::parse($payout->cycle_week_start_date)->toDateString(),
            'cycle_week_end_date' => Carbon::parse($payout->cycle_week_end_date)->toDateString(),
            'appointments_count' => (int) $payout->appointments_count,
            'appointment_revenue' => (float) $payout->appointment_revenue,
            'gross_amount' => (float) $payout->gross_amount,
            'billing_type' => $payout->billing_type,
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

    private function net(float $advancesHeld, float $commission, float $refunds, float $walletRedeemed): float
    {
        // Coins settled against commission give that much back to the salon.
        return round($advancesHeld - $commission - $refunds + $walletRedeemed, 2);
    }

    private function activePlan(string $salonId): ?SalonSubscription
    {
        return SalonSubscription::where('salon_id', $salonId)
            ->where('status', 'active')
            ->orderByDesc('start_date')
            ->first();
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
