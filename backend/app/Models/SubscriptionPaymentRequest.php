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
