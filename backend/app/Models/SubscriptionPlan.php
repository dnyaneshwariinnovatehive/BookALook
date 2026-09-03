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
        'whatsapp_campaign_limit',
        'has_customer_segmentation',
        'has_service_based_targeting',
        'has_high_value_targeting',
        'has_advanced_insights',
        'has_upsell_recommendations',
        'has_cross_sell_recommendations',
        'has_priority_visibility',
        'is_active',
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
    ];
}
