<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class SalonSubscription extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'salon_id',
        'plan_id',
        'feature_level',
        'billing_type',
        'commission_percentage',
        'plan_price_snapshot',
        'start_date',
        'end_date',
        'status',
        'auto_renew',
        'renewed_from_id',
        'cancelled_at',
        'cancelled_by'
    ];

    protected $casts = [
        'commission_percentage' => 'decimal:2',
        'plan_price_snapshot' => 'decimal:2',
        'start_date' => 'date',
        'end_date' => 'date',
        'auto_renew' => 'boolean',
        'cancelled_at' => 'datetime',
    ];

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }

    public function plan()
    {
        return $this->belongsTo(SubscriptionPlan::class, 'plan_id');
    }
}
