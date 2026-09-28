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
