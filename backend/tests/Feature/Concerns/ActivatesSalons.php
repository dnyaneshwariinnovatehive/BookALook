<?php

namespace Tests\Feature\Concerns;

use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPlan;
use App\Support\BillingModel;
use Carbon\Carbon;

/**
 * Customers can only book a salon that is live: approved and on a plan that is
 * in date. Tests that build a salon from scratch use this to put it on one.
 */
trait ActivatesSalons
{
    protected function activateSalon(Salon $salon): Salon
    {
        $plan = SubscriptionPlan::first() ?? SubscriptionPlan::create([
            'name' => 'Test Plan', 'price' => 1999, 'validity_days' => 30, 'is_active' => true,
        ]);

        SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'billing_type' => BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => $plan->price,
            'start_date' => Carbon::today()->subDay(),
            'end_date' => Carbon::today()->addDays(30),
            'status' => 'active',
        ]);

        return $salon;
    }
}
