<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class SubscriptionPlan extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'name',
        'price',
        'validity_days',
        'whatsapp_campaign_limit',
        'has_customer_segmentation',
        'has_service_based_targeting',
        'has_high_value_targeting',
        'has_advanced_insights',
        'has_upsell_recommendations',
        'has_cross_sell_recommendations',
        'has_priority_visibility',
        'is_active',
        'is_commission_plan',
        'created_by'
    ];

    protected $casts = [
        'price' => 'decimal:2',
        'has_customer_segmentation' => 'boolean',
        'has_service_based_targeting' => 'boolean',
        'has_high_value_targeting' => 'boolean',
        'has_advanced_insights' => 'boolean',
        'has_priority_visibility' => 'boolean',
        'is_active' => 'boolean',
        'is_commission_plan' => 'boolean',
    ];

    /**
     * The single plan whose benefits every Commission Model salon enjoys.
     *
     * There is deliberately one, not one per salon: two salons paying the same
     * way should get the same thing, and picking a plan per salon by hand is
     * how they end up differing.
     */
    public static function commissionPlan(): ?self
    {
        return static::where('is_commission_plan', true)->first();
    }

    /**
     * Plans a salon can buy.
     *
     * The plan carrying the Commission Model is an ordinary plan that happens
     * to define what commission salons get. A salon may still buy it outright —
     * doing so simply means paying up front instead of a percentage.
     */
    public function scopePurchasable($query)
    {
        return $query->where('is_active', true);
    }
}
