<?php

namespace App\Services;

use App\Models\Appointment;
use App\Models\Invoice;
use App\Models\InvoiceSetting;
use Illuminate\Support\Facades\DB;

/**
 * Issues the invoice for a confirmed appointment.
 *
 * The totals are not computed here. They are read from
 * AppointmentCheckInService::bill() — the same method the salon settles the
 * balance with — so the number on the customer's invoice and the number the
 * salon asks for at the door are the same number by construction rather than by
 * two pieces of code agreeing to stay in step.
 */
class InvoiceService
{
    public function __construct(private AppointmentCheckInService $checkIn)
    {
    }

    /**
     * Issue the invoice for an appointment, or return the one already issued.
     *
     * Idempotent on purpose. A payment confirmation that is retried, a booking
     * that was free and therefore settled without a gateway, and a double tap
     * on the app all reach here for the same visit, and a customer receiving
     * three documents for one appointment is a support call.
     *
     * Returns null when the appointment has nothing to invoice for, rather than
     * throwing: a booking must never fail because a receipt could not be drawn.
     */
    public function issueFor(Appointment $appointment): ?Invoice
    {
        $existing = Invoice::where('appointment_id', $appointment->id)->first();

        if ($existing) {
            return $existing;
        }

        $template = InvoiceSetting::typed();

        $appointment->load([...$this->checkIn->relations(), 'salon:id,name,address']);
        $bill = $this->checkIn->bill($appointment);

        // A booking with no priced lines is not a document anyone can read, and
        // an all-free basket is a real possibility on this platform.
        if (empty($bill['lines'])) {
            return null;
        }

        return DB::transaction(function () use ($appointment, $bill, $template) {
            return Invoice::create([
                'appointment_id' => $appointment->id,
                'invoice_number' => $this->nextNumber($template),
                'issued_at' => now(),

                'bill_to_name' => $appointment->customer?->name,
                'bill_to_phone' => $appointment->customer?->phone,
                'bill_to_email' => $appointment->customer?->email,

                'salon_name' => $appointment->salon?->name,
                'salon_address' => $appointment->salon?->address,
                'provider_name' => $appointment->servingProvider?->user?->name
                    ?? $appointment->appointedProvider?->user?->name,

                'appointment_date' => $appointment->appointment_date,
                'start_time' => $appointment->start_time,
                'end_time' => $appointment->end_time,

                // Frozen. Names and prices as charged, not as they may be later.
                'line_items' => array_map(fn (array $line) => [
                    'name' => $line['name'],
                    'kind' => $line['kind'],
                    'price' => round((float) $line['price'], 2),
                    'duration_minutes' => (int) $line['duration_minutes'],
                    'provider_name' => $line['provider_name'] ?? null,
                    'added_mid_appointment' => (bool) ($line['added_mid_appointment'] ?? false),
                ], $bill['lines']),

                'subtotal' => $bill['total'],
                'advance_paid' => $bill['advance_paid'],
                'balance_due' => $bill['balance_due'],
                'total' => $bill['total'],

                // Frozen branding, so a later format change leaves this alone.
                'template' => $template,
            ]);
        });
    }

    /**
     * The next number in this year's series: BAL-2026-00001.
     *
     * Allocated from a counter row rather than derived from a count, because
     * two bookings confirming in the same second would otherwise read the same
     * maximum and one of them would collide. The row is locked for the
     * duration of the transaction that spends the number.
     */
    private function nextNumber(array $template): string
    {
        $year = (int) now()->format('Y');
        $key = 'invoice_number_seq_' . $year;

        // Created outside the lock, and with insertOrIgnore because two
        // concurrent first-of-the-year bookings would both try to seed it.
        DB::table('invoice_settings')->insertOrIgnore([
            'setting_key' => $key,
            'setting_value' => '0',
            'data_type' => 'integer',
            'description' => 'Last invoice number issued for ' . $year,
        ]);

        $row = InvoiceSetting::where('setting_key', $key)->lockForUpdate()->firstOrFail();
        $next = ((int) $row->setting_value) + 1;

        $row->update(['setting_value' => (string) $next]);

        $prefix = $this->prefix($template['invoice_number_prefix'] ?? 'BAL');
        $padding = max(1, min(12, (int) ($template['invoice_number_padding'] ?? 5)));

        return sprintf('%s-%d-%0' . $padding . 'd', $prefix, $year, $next);
    }

    /**
     * Keep the prefix to something that reads well in a number and cannot break
     * a column: no spaces, no punctuation, nothing that needs escaping.
     */
    private function prefix(string $raw): string
    {
        $clean = strtoupper(preg_replace('/[^A-Z0-9]/', '', $raw) ?? '');

        return $clean === '' ? 'BAL' : substr($clean, 0, 10);
    }
}
