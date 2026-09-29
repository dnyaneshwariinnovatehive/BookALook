<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Support\Facades\URL;

/**
 * A frozen statement of what BookALook paid a salon for one settled cycle, and
 * what it deducted on the way.
 *
 * The counterpart to Invoice, which says what a customer owes. This is what the
 * salon owner can hold on to: the advances the platform held on their behalf,
 * the commission taken off, refunds adjusted, coins settled, and the net that
 * was actually paid.
 *
 * Nothing here is read live from the payout. A settlement is money that has
 * already moved, and a document that re-derived itself would disagree with the
 * bank the owner is looking at.
 */
class SettlementInvoice extends Model
{
    use HasUuids;

    protected $guarded = [];

    protected $casts = [
        'issued_at' => 'datetime',
        'paid_at' => 'datetime',
        'cycle_start_date' => 'date',
        'cycle_end_date' => 'date',
        'line_items' => 'array',
        'template' => 'array',
        'appointments_count' => 'integer',
        'appointment_revenue' => 'float',
        'advances_held' => 'float',
        'commission_deducted' => 'float',
        'commission_percentage' => 'float',
        'refund_adjustment' => 'float',
        'wallet_redeemed_amount' => 'float',
        'net_amount' => 'float',
    ];

    public function payout()
    {
        return $this->belongsTo(SalonPayout::class);
    }

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }

    /**
     * A time-limited signed link the owner's phone can hand to a browser.
     *
     * Signed rather than authenticated for the same reason the customer invoice
     * is: the thing opening it is a browser, which cannot present a bearer
     * token, and putting the token in the URL would leak it through history and
     * referrers. The signature proves we minted this link for this exact
     * document, and the expiry stops a forwarded link working forever.
     */
    public function temporaryUrl(int $days = 30): string
    {
        return URL::temporarySignedRoute(
            'settlement-invoices.show',
            now()->addDays($days),
            ['invoice' => $this->id],
        );
    }
}
