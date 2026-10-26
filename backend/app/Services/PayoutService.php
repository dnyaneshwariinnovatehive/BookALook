<?php

namespace App\Services;

use App\Models\Appointment;
use App\Models\Salon;
use App\Models\SalonPayout;
use App\Models\SalonPayoutItem;
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

    public function __construct(
        private CommissionService $commission,
        private SettlementInvoiceService $settlementInvoices,
    ) {
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

        // Signed off means frozen: what SuperAdmin approved is what gets paid.
        // Anything that changes afterwards lands in the next payout instead.
        // Likewise once the salon has paid against it: the amount it paid can
        // never move underneath it.
        if ($existing && (in_array($existing->status, [self::STATUS_APPROVED, self::STATUS_DISTRIBUTED], true) || $existing->locked_at)) {
            return $existing;
        }

        return DB::transaction(function () use ($salon, $salonId, $start, $end, $cycleType, $billingModel, $existing) {
            $payout = $existing ?? new SalonPayout([
                'salon_id' => $salonId,
                'cycle_type' => $cycleType,
                'cycle_start_date' => $start->toDateString(),
                'status' => self::STATUS_PENDING,
            ]);
            $payout->fill(['cycle_end_date' => $end->toDateString(), 'billing_type' => $billingModel]);
            $payout->save();

            // A recalculation starts clean: give back everything this payout
            // claimed last time, then claim again from the current facts.
            $payout->items()->delete();
            DB::table('payment_refunds')->where('salon_payout_id', $payout->id)->update(['salon_payout_id' => null]);

            $bookingItems = $this->settleBookings($salon, $payout, $start, $end);
            $refundItems = $this->settleLateRefunds($salonId, $payout);

            // A cycle with nothing in it is not worth a row: an empty payout
            // would only sit on the screen as a ₹0 line to approve.
            if (! $existing && $bookingItems === [] && $refundItems === []) {
                $payout->delete();

                return $payout;
            }

            $gross = round(array_sum(array_column($bookingItems, 'gross_amount')), 2);
            $commission = round(array_sum(array_column($bookingItems, 'commission_amount')), 2);
            $revenue = round(array_sum(array_column($bookingItems, 'commission_base')), 2);
            $refunds = round(array_sum(array_column($refundItems, 'refund_amount')), 2);

            // Coins already settled against this cycle stay put — they were
            // spent deliberately and give the salon back part of the commission.
            $walletRedeemed = (float) ($payout->wallet_redeemed_amount ?? 0);

            $payout->forceFill([
                'gross_amount' => $gross,
                'appointment_revenue' => $revenue,
                'appointments_count' => count($bookingItems),
                'commission_percentage_snapshot' => BillingModel::isCommission($billingModel) && $salon
                    ? $this->commission->currentRate($salon)
                    : 0.0,
                'commission_deducted' => $commission,
                'refund_adjustment' => $refunds,
                'wallet_redeemed_amount' => $walletRedeemed,
                'net_amount' => $this->net($gross, $commission, $refunds, $walletRedeemed),
                'calculated_at' => now(),
            ])->save();

            return $payout->fresh();
        });
    }

    /** Bookings whose money a payout settles. */
    public const LEDGER_STATUSES = ['completed', 'cancelled', 'no_show'];

    /**
     * Claim this cycle's bookings, and write a line for each.
     *
     * A cycle takes the bookings dated inside it. The only older bookings it
     * takes are ones its own cycle can no longer settle — that payout is
     * already approved or paid, so a visit completed late (or a refund decided
     * late) would otherwise never be paid out. A cycle never takes a booking
     * whose own cycle is still open: that used to let "this week" swallow
     * last week's bookings, so every week's figure depended on which one was
     * calculated first.
     *
     *  - Completed: the salon gets the advance the platform took, less any
     *    refund on it; commission is on the full bill.
     *  - Cancelled or no-show: the salon gets whatever of the advance was not
     *    refunded — a forfeited advance is the salon's compensation for the
     *    lost slot — and commission is on that forfeited amount.
     *
     * Commission is only ever on app bookings — walk-ins are free — and at the
     * rate in force on the booking's own date, so a salon that joined the
     * Commission Model mid-month is not charged for the weeks before.
     *
     * @return array<int, array> the lines written
     */
    private function settleBookings(?Salon $salon, SalonPayout $payout, Carbon $start, Carbon $end): array
    {
        if (! $salon) {
            return [];
        }

        $appointments = $this->unclaimed($salon)
            ->whereDate('appointment_date', '<=', $end->toDateString())
            ->where(function ($q) use ($start, $payout) {
                $q->whereDate('appointment_date', '>=', $start->toDateString())
                    // Late: its own cycle is already signed off.
                    ->orWhereExists(function ($frozen) use ($payout) {
                        $frozen->selectRaw('1')
                            ->from('salon_payouts as own')
                            ->whereColumn('own.salon_id', 'appointments.salon_id')
                            ->where('own.id', '!=', $payout->id)
                            ->whereIn('own.status', [self::STATUS_APPROVED, self::STATUS_DISTRIBUTED])
                            ->whereColumn('own.cycle_start_date', '<=', 'appointments.appointment_date')
                            ->whereColumn('own.cycle_end_date', '>=', 'appointments.appointment_date');
                    });
            })
            ->orderBy('appointment_date')
            ->get();

        $lines = [];

        foreach ($appointments as $appointment) {
            $held = $this->heldByPlatform($appointment);
            $refunds = DB::table('payment_refunds')
                ->where('appointment_id', $appointment->id)
                ->where('status', '!=', 'failed')
                ->whereNull('salon_payout_id')
                ->get(['id', 'amount']);
            $refunded = round((float) $refunds->sum('amount'), 2);

            $isApp = $this->isAppBooking($appointment);

            if ($appointment->status === 'completed') {
                $gross = round(max(0, $held - $refunded), 2);
                $base = $isApp ? (float) ($appointment->final_billed_amount ?? $appointment->total_amount) : 0.0;
            } else {
                // Nothing was paid, or all of it went back: nothing to settle.
                $gross = round(max(0, $held - $refunded), 2);
                $base = $isApp ? $gross : 0.0;
            }

            // A walk-in that never touched the platform has nothing in it for
            // a payout either way.
            if ($gross <= 0 && $base <= 0) {
                continue;
            }

            $rate = $isApp ? $this->rateOn($salon, Carbon::parse($appointment->appointment_date)) : 0.0;
            $commission = round($base * $rate / 100, 2);

            $line = [
                'salon_payout_id' => $payout->id,
                'kind' => SalonPayoutItem::KIND_BOOKING,
                'appointment_id' => $appointment->id,
                'appointment_status' => $appointment->status,
                'gross_amount' => $gross,
                'commission_base' => round($base, 2),
                'commission_rate' => $rate,
                'commission_amount' => $commission,
                'refund_amount' => $refunded,
                'net_amount' => round($gross - $commission, 2),
            ];
            SalonPayoutItem::create($line);
            $lines[] = $line;

            if ($refunds->isNotEmpty()) {
                DB::table('payment_refunds')->whereIn('id', $refunds->pluck('id'))->update(['salon_payout_id' => $payout->id]);
            }
        }

        return $lines;
    }

    /**
     * Refunds raised on bookings an earlier, signed-off payout already
     * settled. That money went to the salon, so it comes off this payout.
     *
     * @return array<int, array> the lines written
     */
    private function settleLateRefunds(string $salonId, SalonPayout $payout): array
    {
        $refunds = DB::table('payment_refunds as r')
            ->join('appointments as a', 'a.id', '=', 'r.appointment_id')
            ->join('salon_payout_items as spi', function ($join) {
                $join->on('spi.appointment_id', '=', 'r.appointment_id')
                    ->where('spi.kind', '=', SalonPayoutItem::KIND_BOOKING);
            })
            ->join('salon_payouts as sp', 'sp.id', '=', 'spi.salon_payout_id')
            ->where('a.salon_id', $salonId)
            ->whereNull('r.salon_payout_id')
            ->where('r.status', '!=', 'failed')
            ->where('sp.id', '!=', $payout->id)
            ->whereIn('sp.status', [self::STATUS_APPROVED, self::STATUS_DISTRIBUTED])
            ->get(['r.id', 'r.amount', 'r.appointment_id', 'r.payment_id']);

        $lines = [];

        foreach ($refunds as $refund) {
            $line = [
                'salon_payout_id' => $payout->id,
                'kind' => SalonPayoutItem::KIND_LATE_REFUND,
                'appointment_id' => $refund->appointment_id,
                'payment_id' => $refund->payment_id,
                'payment_refund_id' => $refund->id,
                'gross_amount' => 0,
                'refund_amount' => round((float) $refund->amount, 2),
                'net_amount' => -round((float) $refund->amount, 2),
            ];
            SalonPayoutItem::create($line);
            $lines[] = $line;

            DB::table('payment_refunds')->where('id', $refund->id)->update(['salon_payout_id' => $payout->id]);
        }

        return $lines;
    }

    /** A salon's settle-able bookings that no payout has taken yet. */
    private function unclaimed(Salon $salon)
    {
        return Appointment::where('salon_id', $salon->id)
            ->whereIn('status', self::LEDGER_STATUSES)
            ->when($salon->payout_ledger_since, fn ($q) => $q->whereDate('appointment_date', '>=', Carbon::parse($salon->payout_ledger_since)->toDateString()))
            ->whereNotExists(function ($q) {
                $q->selectRaw('1')
                    ->from('salon_payout_items as spi')
                    ->whereColumn('spi.appointment_id', 'appointments.id')
                    ->where('spi.kind', SalonPayoutItem::KIND_BOOKING);
            });
    }

    /**
     * Earlier cycles a run was never built for, oldest first: cycles before
     * $before holding unclaimed bookings that no payout covers. Each gets its
     * own payout rather than being folded into a later one, so every cycle's
     * figure is that cycle's trading.
     *
     * @return array<int, array{0: Carbon, 1: Carbon}>
     */
    private function missedCycles(Salon $salon, string $cycleType, Carbon $before): array
    {
        $dates = $this->unclaimed($salon)
            ->whereDate('appointment_date', '<', $before->toDateString())
            ->whereNotExists(function ($q) {
                $q->selectRaw('1')
                    ->from('salon_payouts as own')
                    ->whereColumn('own.salon_id', 'appointments.salon_id')
                    ->whereColumn('own.cycle_start_date', '<=', 'appointments.appointment_date')
                    ->whereColumn('own.cycle_end_date', '>=', 'appointments.appointment_date');
            })
            ->distinct()
            ->pluck('appointment_date');

        $cycles = [];
        foreach ($dates as $date) {
            [$s, $e] = PayoutCycle::bounds($cycleType, Carbon::parse($date));
            $cycles[$s->toDateString()] = [$s, $e];
        }
        ksort($cycles);

        return array_values($cycles);
    }

    /**
     * What the platform collected online for this booking. Only payments that
     * went through BookALook's gateway count — money paid at the counter, cash
     * or UPI, is the salon's already.
     */
    private function heldByPlatform(Appointment $appointment): float
    {
        $payments = DB::table('payments')
            ->where('appointment_id', $appointment->id)
            ->where('status', 'success')
            ->whereNotNull('gateway');

        if ($payments->exists()) {
            return round((float) $payments->sum('amount'), 2);
        }

        // Bookings made before payments were recorded per booking carry only
        // their advance figure. A completed app booking was paid for, so that
        // figure stands; a cancelled one with no payment row was never paid.
        return $appointment->status === 'completed' && $this->isAppBooking($appointment)
            ? (float) $appointment->advance_amount
            : 0.0;
    }

    /** Booked through the app, as opposed to a walk-in the salon entered. */
    private function isAppBooking(Appointment $appointment): bool
    {
        return ! in_array($appointment->booking_source, ['walk_in', 'offline'], true)
            && $appointment->walk_in_customer_name === null;
    }

    /**
     * The commission rate in force on a date: from the salon's rate history,
     * which opens when it joins the Commission Model and closes when it
     * leaves, so a day outside it is commission-free.
     */
    private function rateOn(Salon $salon, Carbon $date): float
    {
        $hasHistory = \App\Models\SalonCommissionRate::where('salon_id', $salon->id)->exists();

        if (! $hasHistory) {
            // A commission salon from before rate history was kept.
            return $salon->isOnCommissionModel() ? $this->commission->currentRate($salon) : 0.0;
        }

        $rate = \App\Models\SalonCommissionRate::where('salon_id', $salon->id)
            ->whereDate('effective_from', '<=', $date->toDateString())
            ->where(fn ($q) => $q->whereDate('effective_to', '>=', $date->toDateString())
                // A rate left open is only live while the salon is still on the
                // Commission Model; leaving it closes the rate, and a stray open
                // one must not charge a Subscription Plan salon.
                ->orWhere(fn ($open) => $open->whereNull('effective_to')->whereRaw('? = 1', [$salon->isOnCommissionModel() ? 1 : 0])))
            ->orderByDesc('effective_from')
            ->first();

        return (float) ($rate->percentage ?? 0);
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
        return DB::transaction(function () use ($payout, $actor) {
            $payout = SalonPayout::whereKey($payout->id)->lockForUpdate()->firstOrFail();

            if ($payout->status === self::STATUS_DISTRIBUTED) {
                throw new \RuntimeException('This payout has already been distributed.');
            }

            $this->assertCycleFinished($payout);

            // From here the figures are frozen; anything later goes to the
            // next payout.
            $payout->forceFill([
                'status' => self::STATUS_APPROVED,
                'approved_by' => $actor->id,
                'approved_at' => now(),
            ])->save();

            return $payout->fresh();
        });
    }

    /**
     * Record that the net amount has been paid out.
     *
     * The commission comes off here, in the same cycle, before the record is
     * closed — the salon receives the net and the deduction stays on the record
     * for both sides to refer to. Settling a Commission Model month also buys
     * the salon the month that follows it.
     *
     * The settlement statement is drawn once the money is recorded, not before,
     * and outside the transaction. A statement is the last step, never the one
     * that can fail: the salon has already been paid by the time it is drawn,
     * so a problem producing the document must not undo the payment or leave the
     * owner without one.
     */
    public function markDistributed(SalonPayout $payout, User $actor, ?string $reference, ?string $notes = null): SalonPayout
    {
        $payout = DB::transaction(function () use ($payout, $actor, $reference, $notes) {
            // Locked and re-read, so two clicks cannot both get past the
            // status check and record the money moving twice.
            $payout = SalonPayout::whereKey($payout->id)->lockForUpdate()->firstOrFail();

            if ($payout->status === self::STATUS_DISTRIBUTED) {
                throw new \RuntimeException('This payout has already been distributed.');
            }

            $this->assertCycleFinished($payout);

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

        try {
            $this->settlementInvoices->issueFor($payout);
        } catch (\Throwable $e) {
            // Reported, not swallowed silently, and never rethrown. The payout
            // is distributed and that is not reversible.
            report($e);
        }

        return $payout->fresh();
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
            // Which way the money moves. A Commission Model salon whose
            // commission is more than the advances held owes the difference;
            // it pays offline and SuperAdmin marks it collected.
            'direction' => (float) $payout->net_amount < 0 ? 'salon_owes' : 'pay_salon',
            'amount_due' => abs((float) $payout->net_amount),
            // The salon has paid against it, so the figures are fixed.
            'locked' => $payout->locked_at !== null,
            // The latest screenshot the salon sent for what it owes, if any.
            'payment_submission' => $this->latestSubmission($payout)?->present(),
            'status' => $payout->status,
            // Still running: a preview that cannot be approved or paid yet.
            'in_progress' => self::cycleInProgress($payout),
            'approved_at' => $payout->approved_at,
            'distributed_at' => $payout->distributed_at,
            'distribution_reference' => $payout->distribution_reference,
            'notes' => $payout->notes,
            'settlement_invoice' => $this->settlementInvoiceState($payout),
        ];
    }

    /**
     * What a client needs to open the settlement statement for this payout: the
     * reference to quote, and a link that is regenerated on read rather than
     * stored, so a link that has expired is replaced instead of being a dead
     * button forever.
     *
     * Null until the payout is distributed, which is also the only point at
     * which a document exists.
     *
     * @return array{number: string, issued_at: string, url: string}|null
     */
    private function latestSubmission(SalonPayout $payout): ?\App\Models\PayoutPaymentSubmission
    {
        return $payout->relationLoaded('paymentSubmissions')
            ? $payout->paymentSubmissions->sortByDesc('created_at')->first()
            : $payout->paymentSubmissions()->latest()->first();
    }

    private function settlementInvoiceState(SalonPayout $payout): ?array
    {
        $invoice = $payout->relationLoaded('settlementInvoice')
            ? $payout->settlementInvoice
            : $payout->settlementInvoice()->first();

        if (! $invoice) {
            return null;
        }

        return [
            'number' => $invoice->invoice_number,
            'issued_at' => $invoice->issued_at?->toIso8601String(),
            'url' => $invoice->temporaryUrl(),
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
        // Every salon on this rhythm with anything still to settle up to the
        // cycle's end — bookings no payout has taken yet, including late
        // completions and weeks a missed run never built — or a refund on a
        // booking already settled, or this cycle's payout already open.
        $unsettled = Appointment::whereIn('status', self::LEDGER_STATUSES)
            ->whereDate('appointment_date', '<=', $end->toDateString())
            ->whereNotExists(function ($q) {
                $q->selectRaw('1')
                    ->from('salon_payout_items as spi')
                    ->whereColumn('spi.appointment_id', 'appointments.id')
                    ->where('spi.kind', SalonPayoutItem::KIND_BOOKING);
            })
            ->distinct()
            ->pluck('salon_id');

        $lateRefunds = DB::table('payment_refunds as r')
            ->join('appointments as a', 'a.id', '=', 'r.appointment_id')
            ->whereNull('r.salon_payout_id')
            ->where('r.status', '!=', 'failed')
            ->distinct()
            ->pluck('a.salon_id');

        $open = SalonPayout::where('cycle_type', $cycleType)
            ->whereDate('cycle_start_date', $start->toDateString())
            ->where('status', self::STATUS_PENDING)
            ->pluck('salon_id');

        // Only the salons settling on this rhythm. A salon that switched models
        // settles on whichever one it is on now; bookings it already settled
        // the other way are never taken again.
        $salonIds = Salon::whereIn('id', $unsettled->merge($lateRefunds)->merge($open)->unique()->values())
            ->where('commission_opt_in', BillingModel::isCommission($billingModel))
            ->pluck('id');

        foreach ($salonIds as $salonId) {
            $salon = Salon::find($salonId);

            // Weeks (or months) no run was ever built for are built first, as
            // their own payouts, so nothing is lost and nothing is merged.
            foreach ($salon ? $this->missedCycles($salon, $cycleType, $start) : [] as [$missedStart, $missedEnd]) {
                $this->calculate($salonId, $missedStart, $missedEnd, $cycleType);
            }

            $this->calculate($salonId, $start, $end, $cycleType);
        }

        $salonIds = SalonPayout::where('cycle_type', $cycleType)
            ->whereDate('cycle_start_date', $start->toDateString())
            ->whereIn('salon_id', $salonIds)
            ->pluck('salon_id');

        return [
            'cycle_type' => $cycleType,
            'start' => $start->toDateString(),
            'end' => $end->toDateString(),
            'payouts' => $salonIds->count(),
        ];
    }

    /**
     * A cycle still running is a preview: its bookings are not all in yet, so
     * it cannot be signed off or paid until its last day is over.
     */
    public static function cycleInProgress(SalonPayout $payout): bool
    {
        return $payout->cycle_end_date !== null
            && Carbon::parse($payout->cycle_end_date)->startOfDay()->gte(Carbon::today());
    }

    private function assertCycleFinished(SalonPayout $payout): void
    {
        if (self::cycleInProgress($payout)) {
            throw new \RuntimeException(sprintf(
                'This cycle runs until %s. It can be approved and paid once it has ended.',
                Carbon::parse($payout->cycle_end_date)->format('j M Y')
            ));
        }
    }

    private function net(float $advancesHeld, float $commission, float $refunds, float $walletRedeemed): float
    {
        // Coins settled against commission give that much back to the salon.
        return round($advancesHeld - $commission - $refunds + $walletRedeemed, 2);
    }

}
