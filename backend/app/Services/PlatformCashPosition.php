<?php

namespace App\Services;

use App\Models\SalonPayoutItem;
use Illuminate\Support\Facades\DB;

/**
 * "Money in pocket": what BookALook holds right now, and how much of it is
 * really its own.
 *
 * Two figures, worked out from the ledgers rather than from a bank feed:
 *
 *   cash held  = customer payments collected online
 *              − estimated Razorpay fee (BookALook absorbs it)
 *              − refunds already sent back to customers
 *              − payouts already paid to salons
 *              + commission dues salons have paid in
 *              + Subscription Plan payments salons have paid in
 *
 *   in pocket  = cash held
 *              − refunds still on their way to customers
 *              − payouts signed off or calculated but not yet paid to salons
 *              − advances held for bookings no payout has taken yet
 *
 * So "in pocket" is the cash BookALook keeps once everything it already owes
 * has gone out. Money salons still owe BookALook (open commission dues, plan
 * payments awaiting verification) is reported apart and never counted: it is
 * not in the bank until it arrives.
 *
 * Only payments that went through the gateway count — what a customer pays at
 * the counter is the salon's from the start. Razorpay's fee is not reported
 * per payment, so it is estimated at `services.payments.razorpay.fee_percent`.
 */
class PlatformCashPosition
{
    public function snapshot(): array
    {
        $collected = DB::table('payments')
            ->where('status', 'success')
            ->whereNotNull('gateway')
            ->selectRaw("count(*) as n, coalesce(sum(amount), 0) as total, coalesce(sum(case when gateway = 'razorpay' then amount else 0 end), 0) as razorpay")
            ->first();

        $feePercent = (float) config('services.payments.razorpay.fee_percent', 2.36);
        $fee = round((float) $collected->razorpay * $feePercent / 100, 2);

        $refunds = DB::table('payment_refunds as r')
            ->join('payments as p', 'p.id', '=', 'r.payment_id')
            ->whereNotNull('p.gateway')
            ->where('r.status', '!=', 'failed')
            ->selectRaw("
                coalesce(sum(case when r.status = 'processed' then r.amount else 0 end), 0) as paid,
                sum(case when r.status = 'processed' then 1 else 0 end) as paid_n,
                coalesce(sum(case when r.status <> 'processed' then r.amount else 0 end), 0) as queued,
                sum(case when r.status <> 'processed' then 1 else 0 end) as queued_n
            ")
            ->first();

        $payouts = DB::table('salon_payouts')
            ->selectRaw("
                coalesce(sum(case when status = ? and net_amount > 0 then net_amount else 0 end), 0) as paid_out,
                sum(case when status = ? and net_amount > 0 then 1 else 0 end) as paid_out_n,
                coalesce(sum(case when status = ? and net_amount < 0 then -net_amount else 0 end), 0) as dues_in,
                sum(case when status = ? and net_amount < 0 then 1 else 0 end) as dues_in_n,
                coalesce(sum(case when status <> ? and net_amount > 0 then net_amount else 0 end), 0) as owed,
                sum(case when status <> ? and net_amount > 0 then 1 else 0 end) as owed_n,
                coalesce(sum(case when status <> ? and net_amount < 0 then -net_amount else 0 end), 0) as receivable,
                sum(case when status <> ? and net_amount < 0 then 1 else 0 end) as receivable_n,
                coalesce(sum(case when status = ? then commission_deducted - coalesce(wallet_redeemed_amount, 0) else 0 end), 0) as commission_kept
            ", array_fill(0, 9, PayoutService::STATUS_DISTRIBUTED))
            ->first();

        // Plan payments are cash as transferred: after coins. Older requests
        // predate amount_payable_inr, so the plan price less coins stands in.
        $plans = DB::table('subscription_payment_requests as r')
            ->leftJoin('subscription_plans as p', 'p.id', '=', 'r.subscription_plan_id')
            ->selectRaw("
                coalesce(sum(case when r.status = 'approved' then
                    case when r.amount_payable_inr is not null then r.amount_payable_inr
                         when coalesce(p.price, 0) > coalesce(r.coin_discount_inr, 0) then coalesce(p.price, 0) - coalesce(r.coin_discount_inr, 0)
                         else 0 end
                else 0 end), 0) as approved,
                sum(case when r.status = 'approved' then 1 else 0 end) as approved_n,
                coalesce(sum(case when r.status = 'pending' then coalesce(r.amount_payable_inr, p.price, 0) else 0 end), 0) as pending,
                sum(case when r.status = 'pending' then 1 else 0 end) as pending_n
            ")
            ->first();

        // Advances on bookings no payout has claimed yet: upcoming visits, and
        // finished ones the next run will settle. Refunds against them have
        // already left (or are queued above), so they come off here.
        $unclaimed = fn ($q, string $column) => $q->whereNotExists(function ($w) use ($column) {
            $w->selectRaw('1')->from('salon_payout_items as spi')
                ->whereColumn('spi.appointment_id', $column)
                ->where('spi.kind', SalonPayoutItem::KIND_BOOKING);
        });

        $heldUnclaimed = $unclaimed(
            DB::table('payments as p')->where('p.status', 'success')->whereNotNull('p.gateway')->whereNotNull('p.appointment_id'),
            'p.appointment_id'
        )->selectRaw('coalesce(sum(p.amount), 0) as total, count(distinct p.appointment_id) as bookings')->first();

        $refundedUnclaimed = (float) $unclaimed(
            DB::table('payment_refunds as r')->join('payments as p', 'p.id', '=', 'r.payment_id')
                ->whereNotNull('p.gateway')->where('r.status', '!=', 'failed'),
            'r.appointment_id'
        )->sum('r.amount');

        $unsettled = round(max(0, (float) $heldUnclaimed->total - $refundedUnclaimed), 2);

        $cashHeld = round(
            (float) $collected->total - $fee - (float) $refunds->paid - (float) $payouts->paid_out
            + (float) $payouts->dues_in + (float) $plans->approved,
            2
        );
        $stillOwed = round((float) $refunds->queued + (float) $payouts->owed + $unsettled, 2);

        $line = fn (string $key, string $label, float $amount, int $count, string $hint) => [
            'key' => $key, 'label' => $label, 'amount' => round($amount, 2), 'count' => $count, 'hint' => $hint,
        ];

        return [
            'in_pocket' => round($cashHeld - $stillOwed, 2),
            'cash_held' => $cashHeld,
            'still_owed' => $stillOwed,
            'fee_percent' => $feePercent,
            'cash_in' => [
                $line('online_collected', 'Customer payments collected online', (float) $collected->total, (int) $collected->n, 'Advances and full payments through the gateway'),
                $line('plan_payments', 'Subscription Plan payments', (float) $plans->approved, (int) $plans->approved_n, 'Bank transfers you approved, after coins'),
                $line('dues_collected', 'Commission dues paid by salons', (float) $payouts->dues_in, (int) $payouts->dues_in_n, 'Commission Model payouts where the salon paid BookALook'),
            ],
            'cash_out' => [
                $line('paid_to_salons', 'Paid out to salons', (float) $payouts->paid_out, (int) $payouts->paid_out_n, 'Distributed payouts, net of commission'),
                $line('refunds_paid', 'Refunds sent to customers', (float) $refunds->paid, (int) $refunds->paid_n, 'Processed refunds of online payments'),
                $line('gateway_fee', 'Razorpay fee (estimated)', $fee, 0, sprintf('%s%% of Razorpay collections — BookALook absorbs it', rtrim(rtrim(number_format($feePercent, 2), '0'), '.'))),
            ],
            'owed_out' => [
                $line('open_payouts', 'Payouts not yet paid to salons', (float) $payouts->owed, (int) $payouts->owed_n, 'Pending and approved payouts BookALook owes'),
                $line('unsettled_advances', 'Advances for bookings not yet settled', $unsettled, (int) $heldUnclaimed->bookings, 'Upcoming visits and ones the next payout run will take'),
                $line('refunds_queued', 'Refunds still on their way', (float) $refunds->queued, (int) $refunds->queued_n, 'Pending, processing or awaiting manual payout'),
            ],
            'not_counted' => [
                $line('dues_receivable', 'Commission dues salons still owe', (float) $payouts->receivable, (int) $payouts->receivable_n, 'Counted once the salon pays'),
                $line('plans_pending', 'Plan payments awaiting your check', (float) $plans->pending, (int) $plans->pending_n, 'Counted once you approve them'),
            ],
            'commission_kept' => round((float) $payouts->commission_kept, 2),
        ];
    }
}
