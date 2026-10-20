<?php

namespace Database\Seeders;

use App\Models\SubscriptionPlan;
use Illuminate\Database\Seeder;

class SubscriptionPlanSeeder extends Seeder
{
    /**
     * Seed the default subscription plans for onboarding and purchasing.
     */
    public function run(): void
    {
        SubscriptionPlan::updateOrCreate(
            ['name' => 'Starter'],
            [
                'price' => 1999.00,
                'validity_days' => 30,
                'whatsapp_campaign_limit' => 250,
                'has_customer_segmentation' => true,
                'has_service_based_targeting' => false,
                'has_high_value_targeting' => false,
                'has_advanced_insights' => false,
                'has_upsell_recommendations' => 'basic',
                'has_cross_sell_recommendations' => 'none',
                'has_priority_visibility' => false,
                'is_active' => true,
                'is_commission_plan' => false,
            ]
        );

        SubscriptionPlan::updateOrCreate(
            ['name' => 'Growth'],
            [
                'price' => 2999.00,
                'validity_days' => 30,
                'whatsapp_campaign_limit' => 1000,
                'has_customer_segmentation' => true,
                'has_service_based_targeting' => true,
                'has_high_value_targeting' => true,
                'has_advanced_insights' => true,
                'has_upsell_recommendations' => 'advanced',
                'has_cross_sell_recommendations' => 'advanced',
                'has_priority_visibility' => true,
                'is_active' => true,
                'is_commission_plan' => true,
            ]
        );

        SubscriptionPlan::updateOrCreate(
            ['name' => 'Enterprise Annual'],
            [
                'price' => 24999.00,
                'validity_days' => 365,
                'whatsapp_campaign_limit' => 15000,
                'has_customer_segmentation' => true,
                'has_service_based_targeting' => true,
                'has_high_value_targeting' => true,
                'has_advanced_insights' => true,
                'has_upsell_recommendations' => 'advanced',
                'has_cross_sell_recommendations' => 'advanced',
                'has_priority_visibility' => true,
                'is_active' => true,
                'is_commission_plan' => false,
            ]
        );
    }
}
