<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

/**
 * One movement of coins, and the reason for it.
 *
 * Every row keeps the balance it produced and the rupee value of a coin at the
 * time, so a later change to the coin rate cannot rewrite what a past
 * redemption was worth.
 */
class WalletTransaction extends Model
{
    use HasUuids;

    public const TYPE_EARNED = 'earned';
    public const TYPE_REDEEMED = 'redeemed';
    public const TYPE_ADJUSTMENT = 'adjustment';
    public const TYPE_EXPIRED = 'expired';

    protected $fillable = [
        'salon_id',
        'type',
        'coins',
        'balance_after',
        'coin_value_snapshot',
        'related_scheme_tier_id',
        'related_appointment_id',
        'related_payout_id',
        'related_subscription_id',
        'created_by',
        'note',
    ];

    protected $casts = [
        'coins' => 'integer',
        'balance_after' => 'integer',
        'coin_value_snapshot' => 'decimal:2',
    ];

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }

    public function tier()
    {
        return $this->belongsTo(WalletSchemeTier::class, 'related_scheme_tier_id');
    }

    public function appointment()
    {
        return $this->belongsTo(Appointment::class, 'related_appointment_id');
    }

    public function payout()
    {
        return $this->belongsTo(SalonPayout::class, 'related_payout_id');
    }

    public function subscription()
    {
        return $this->belongsTo(SalonSubscription::class, 'related_subscription_id');
    }

    public function creator()
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
