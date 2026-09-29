<?php

namespace App\Models;

use App\Support\PayoutCycle;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class SalonPayout extends Model
{
    use HasUuids;

    protected $guarded = [];

    protected $casts = [
        'cycle_start_date' => 'date',
        'cycle_end_date' => 'date',
        'calculated_at' => 'datetime',
        'approved_at' => 'datetime',
        'distributed_at' => 'datetime',
    ];

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }

    /**
     * The statement drawn when this payout was distributed. Absent until the
     * money moves, and absent forever if the cycle settled to nothing.
     *
     * The key is spelled out because Eloquent's convention would derive
     * `salon_payout_id` from this class's own name, and the column is
     * `payout_id`. Left to the convention the relation reads as always null —
     * an invoice number that quietly never appears.
     */
    public function settlementInvoice()
    {
        return $this->hasOne(SettlementInvoice::class, 'payout_id');
    }

    public function scopeMonthly($query)
    {
        return $query->where('cycle_type', PayoutCycle::MONTHLY);
    }

    public function scopeWeekly($query)
    {
        return $query->where('cycle_type', PayoutCycle::WEEKLY);
    }

    /** Money that has not moved yet, and so still blocks a rate change. */
    public function scopeUnsettled($query)
    {
        return $query->where('status', '!=', 'distributed');
    }
}
