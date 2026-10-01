<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

/**
 * A frozen statement of what a customer owed and has paid for one appointment.
 *
 * Nothing here is read live from the booking. See the migration for why: an
 * invoice that re-derived itself from the appointment would change under the
 * customer's feet every time the salon added a service mid-visit.
 */
class Invoice extends Model
{
    use HasUuids;

    protected $guarded = [];

    protected $casts = [
        'issued_at' => 'datetime',
        'appointment_date' => 'date',
        'line_items' => 'array',
        'template' => 'array',
        'subtotal' => 'float',
        'advance_paid' => 'float',
        'balance_due' => 'float',
        'total' => 'float',
    ];

    public function appointment()
    {
        return $this->belongsTo(Appointment::class);
    }

    // ------------------------------------------------------------ when

    /**
     * The three labels a customer reads the appointment by.
     *
     * These exist because the obvious way to write this — gluing the date and the
     * time together and handing the result to Carbon — is wrong, and wrong in a
     * way that only shows up on the page it breaks. `appointment_date` is a
     * `date` column, but Laravel stores a string it was given through the model's
     * *datetime* format, so the attribute can be either `2026-10-02` or
     * `2026-10-02 00:00:00` depending on whether the row was just written or just
     * read. Concatenated with a time either way, that is either a valid string or
     * `2026-10-02 00:00:00 10:00`, which Carbon rejects outright. Both the screen
     * view and the PDF used to do this, so a freshly issued invoice had no date on
     * it at all.
     *
     * Formatting the parts separately sidesteps the question entirely: a date is
     * read from the first ten characters, a time from its own digits, and neither
     * is ever asked to parse the other.
     */
    public function appointmentDateLabel(): string
    {
        return $this->datePart()->format('D, d M Y');
    }

    public function startTimeLabel(): string
    {
        return $this->timePart($this->start_time)->format('g:i A');
    }

    public function endTimeLabel(): string
    {
        return $this->timePart($this->end_time)->format('g:i A');
    }

    private function datePart(): \Carbon\Carbon
    {
        $value = $this->appointment_date;

        if ($value instanceof \DateTimeInterface) {
            return \Carbon\Carbon::instance($value);
        }

        return \Carbon\Carbon::parse(\Illuminate\Support\Str::of((string) $value)->substr(0, 10));
    }

    private function timePart(mixed $value): \Carbon\Carbon
    {
        if ($value instanceof \DateTimeInterface) {
            return \Carbon\Carbon::instance($value);
        }

        // '9:05', '09:05', '09:05:00' — with or without the seconds.
        preg_match('/(\d{1,2}):(\d{2})/', (string) $value, $m);

        return \Carbon\Carbon::createFromFormat(
            'H:i',
            sprintf('%02d:%s', (int) ($m[1] ?? 0), $m[2] ?? '00')
        );
    }

    /**
     * A time-limited signed link the app can hand to a browser or WebView.
     *
     * Signed rather than authenticated because the thing opening it is a
     * WebView, which cannot present a bearer token — and putting the token in
     * the URL would leak it through history and referrers. The signature proves
     * the link was minted by us for this exact invoice, and the expiry stops a
     * forwarded link working forever.
     */
    public function temporaryUrl(int $days = 30): string
    {
        return \Illuminate\Support\Facades\URL::temporarySignedRoute(
            'invoices.show',
            now()->addDays($days),
            ['invoice' => $this->id],
        );
    }
}
