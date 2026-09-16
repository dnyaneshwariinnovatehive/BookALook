<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SubscriptionPaymentRequest extends Model
{
    protected $fillable = [
        'salon_id',
        'subscription_plan_id',
        'billing_type',
        'screenshot_url',
        'status',
        // The coins the owner put towards this plan. Held as intent until
        // SuperAdmin approves — a request that is never approved must not have
        // cost the salon anything.
        'coins_to_redeem',
        'coin_discount_inr',
        'amount_payable_inr',
    ];

    protected $casts = [
        'coins_to_redeem' => 'integer',
        'coin_discount_inr' => 'decimal:2',
        'amount_payable_inr' => 'decimal:2',
    ];

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }

    public function plan()
    {
        return $this->belongsTo(SubscriptionPlan::class, 'subscription_plan_id');
    }
}
