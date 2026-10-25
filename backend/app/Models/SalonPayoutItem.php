<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * One line of a salon payout: a booking it settled, or a refund on a booking
 * an earlier payout had already settled.
 */
class SalonPayoutItem extends Model
{
    use HasUuids;

    public const KIND_BOOKING = 'booking';
    public const KIND_LATE_REFUND = 'late_refund';

    protected $guarded = [];

    protected $casts = [
        'gross_amount' => 'float',
        'commission_base' => 'float',
        'commission_rate' => 'float',
        'commission_amount' => 'float',
        'refund_amount' => 'float',
        'net_amount' => 'float',
    ];

    public function payout()
    {
        return $this->belongsTo(SalonPayout::class, 'salon_payout_id');
    }

    public function appointment()
    {
        return $this->belongsTo(Appointment::class);
    }
}
