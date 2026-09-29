<?php

namespace App\Services;

use App\Models\InvoiceSetting;
use App\Models\SettlementInvoice;
use App\Models\Salon;
use App\Models\SalonPayout;
use App\Support\BillingModel;
use App\Support\PayoutCycle;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Issues the settlement invoice for a cycle of money paid out to a salon.
 *
 * The arithmetic is not computed here. Every figure is read off the payout row
 * that PayoutService has already frozen by marking it distributed, so the
 * statement and the record the salon is being settled against are the same
 * numbers by construction rather than by two pieces of code agreeing to stay in
 * step.
 *
 * The line items are therefore a presentation of the payout's own components,
 * not a second calculation of them. That is deliberate: the one thing a money
 * document must never do is disagree with the ledger behind it.
 */
class SettlementInvoiceService
{
    /**
     * Issue the settlement invoice for a payout, or return the one already issued.
     *
     * Idempotent on purpose. markDistributed() is guarded against a second
     * distribution, but a retry of the request that triggered it should not be
     * able to mint a second document for the same money, and neither should a
     * manual re-run of the demo seeder.
     *
     * Returns null when the payout settled nothing, rather than throwing: a
     * settlement must never fail because a statement could not be drawn.
     */
    public function issueFor(SalonPayout $payout): ?SettlementInvoice
    {
        $existing = SettlementInvoice::where('payout_id', $payout->id)->first();

        if ($existing) {
            return $existing;
        }

        $template = InvoiceSetting::typed();

        // load(), not loadMissing(): callers eager-load this relation with only
        // the columns their own screen needs, and a missing-then-skipped load
        // would silently leave the address and owner name off the statement.
        $payout->load(['salon' => fn ($query) => $query->with('admin:id,name')]);

        // A cycle that paid out nothing is not a document anyone can act on,
        // and an all-zero statement is a real possibility on a quiet week.
        if ((float) $payout->net_amount == 0.0) {
            return null;
        }

        $lineItems = $this->lineItems($payout);

        return DB::transaction(function () use ($payout, $template, $lineItems) {
            return SettlementInvoice::create([
                'payout_id' => $payout->id,
                'invoice_number' => $this->nextNumber($template),
                'issued_at' => now(),
                'paid_at' => $payout->distributed_at,

                'salon_id' => $payout->salon_id,
                'salon_name' => $payout->salon?->name,
                'salon_address' => $this->addressLine($payout->salon),
                'salon_phone' => $payout->salon?->phone_num,
                'owner_name' => $payout->salon?->admin?->name,

                'billing_type' => BillingModel::normalise($payout->billing_type),
                'cycle_type' => $payout->cycle_type ?? PayoutCycle::WEEKLY,
                'cycle_start_date' => $payout->cycle_start_date,
                'cycle_end_date' => $payout->cycle_end_date,
                'cycle_label' => PayoutCycle::label(
                    $payout->cycle_type ?? PayoutCycle::WEEKLY,
                    Carbon::parse($payout->cycle_start_date),
                    Carbon::parse($payout->cycle_end_date),
                ),

                // Frozen. The components as they stood when the money moved.
                'line_items' => $lineItems,
                'appointments_count' => (int) $payout->appointments_count,
                'appointment_revenue' => round((float) $payout->appointment_revenue, 2),
                'advances_held' => round((float) $payout->gross_amount, 2),
                'commission_deducted' => round((float) $payout->commission_deducted, 2),
                'commission_percentage' => round((float) $payout->commission_percentage_snapshot, 2),
                'refund_adjustment' => round((float) $payout->refund_adjustment, 2),
                'wallet_redeemed_amount' => round((float) $payout->wallet_redeemed_amount, 2),
                'net_amount' => round((float) $payout->net_amount, 2),

                'distribution_reference' => $payout->distribution_reference,

                // Frozen branding, so a later format change leaves this alone.
                'template' => $template,
            ]);
        });
    }

    /**
     * The statement, as signed amounts so a deduction reads as a deduction.
     *
     * Only the components that are actually non-zero are listed. A subscription
     * plan salon has no commission to explain, and a "Commission at 0.00%: ₹0"
     * row teaches the owner to stop reading the document.
     *
     * @return array<int, array{name: string, detail: ?string, amount: float}>
     */
    private function lineItems(SalonPayout $payout): array
    {
        $advances = round((float) $payout->gross_amount, 2);
        $commission = round((float) $payout->commission_deducted, 2);
        $refunds = round((float) $payout->refund_adjustment, 2);
        $coins = round((float) $payout->wallet_redeemed_amount, 2);

        $lines = [];

        if ($advances != 0.0) {
            $lines[] = [
                'name' => 'Advances collected by BookALook for you',
                'detail' => PayoutCycle::label(
                    $payout->cycle_type ?? PayoutCycle::WEEKLY,
                    Carbon::parse($payout->cycle_start_date),
                    Carbon::parse($payout->cycle_end_date),
                ),
                'amount' => $advances,
            ];
        }

        if ($commission != 0.0) {
            $rate = (float) $payout->commission_percentage_snapshot;
            $lines[] = [
                'name' => sprintf('Commission at %s%%', rtrim(rtrim(number_format($rate, 2), '0'), '.')),
                'detail' => sprintf(
                    'on %s billed by you in this period',
                    $this->money($payout->appointment_revenue),
                ),
                'amount' => -$commission,
            ];
        }

        if ($refunds != 0.0) {
            $lines[] = [
                'name' => 'Refunds adjusted',
                'detail' => 'Customer refunds raised in this period',
                'amount' => -$refunds,
            ];
        }

        if ($coins != 0.0) {
            $lines[] = [
                'name' => 'Coins settled against commission',
                'detail' => 'Rewards coins applied to this period',
                'amount' => $coins,
            ];
        }

        return $lines;
    }

    /**
     * The next number in this year's settlement series: SET-2026-00001.
     *
     * A separate counter from the customer invoice series, stored the same way
     * and for the same reason: a row locked for the duration of the transaction
     * that spends the number, rather than a count that two simultaneous
     * settlements would read identically.
     */
    private function nextNumber(array $template): string
    {
        $year = (int) now()->format('Y');
        $key = 'settlement_invoice_number_seq_' . $year;

        // Created outside the lock, and with insertOrIgnore because two
        // concurrent first-of-the-year settlements would both try to seed it.
        DB::table('invoice_settings')->insertOrIgnore([
            'setting_key' => $key,
            'setting_value' => '0',
            'data_type' => 'integer',
            'description' => 'Last settlement invoice number issued for ' . $year,
        ]);

        $row = InvoiceSetting::where('setting_key', $key)->lockForUpdate()->firstOrFail();
        $next = ((int) $row->setting_value) + 1;

        $row->update(['setting_value' => (string) $next]);

        $prefix = $this->prefix($template['settlement_invoice_number_prefix'] ?? 'SET');
        $padding = max(1, min(12, (int) ($template['settlement_invoice_number_padding'] ?? 5)));

        return sprintf('%s-%d-%0' . $padding . 'd', $prefix, $year, $next);
    }

    /**
     * Keep the prefix to something that reads well in a number and cannot break
     * a column: no spaces, no punctuation, nothing that needs escaping.
     */
    private function prefix(string $raw): string
    {
        $clean = strtoupper(preg_replace('/[^A-Z0-9]/', '', $raw) ?? '');

        return $clean === '' ? 'SET' : substr($clean, 0, 10);
    }

    /**
     * The salon's address on one line, without the parts it has not filled in.
     */
    private function addressLine(?Salon $salon): ?string
    {
        if (! $salon) {
            return null;
        }

        $parts = array_filter([
            $salon->address,
            $salon->city,
            $salon->pincode,
        ]);

        return $parts ? implode(', ', $parts) : null;
    }

    private function money(float $amount): string
    {
        return '₹' . number_format($amount, 2);
    }
}
