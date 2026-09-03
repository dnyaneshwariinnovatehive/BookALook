<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\SubscriptionPlan;
use App\Models\Salon;
use App\Models\SalonSubscription;
use Illuminate\Support\Carbon;

class SubscriptionPlanController extends Controller
{
    /**
     * Get all master subscription plans.
     */
    public function index()
    {
        $plans = SubscriptionPlan::all();
        
        // Also get all salons with their current subscription so superadmin can assign/override plans
        $salons = Salon::with(['currentSubscription.plan', 'admin'])->get()->map(function($salon) {
            return [
                'id' => $salon->id,
                'name' => $salon->name,
                'owner' => $salon->admin ? $salon->admin->name : 'Unknown',
                'current_plan' => $salon->currentSubscription ? $salon->currentSubscription->plan->name : 'None',
                'billing_type' => $salon->currentSubscription ? $salon->currentSubscription->billing_type : 'N/A',
                'commission_percentage' => $salon->currentSubscription ? $salon->currentSubscription->commission_percentage : null,
                'expiry' => $salon->currentSubscription ? $salon->currentSubscription->end_date->format('Y-m-d') : null,
                'status' => $salon->currentSubscription ? $salon->currentSubscription->status : 'N/A',
            ];
        });

        return response()->json([
            'success' => true,
            'plans' => $plans,
            'salons' => $salons
        ]);
    }

    /**
     * Create a new master subscription plan.
     */
    public function store(Request $request)
    {
        $validated = $request->validate([
            'name' => 'required|string|max:50',
            'price' => 'required|numeric',
            'whatsapp_campaign_limit' => 'required|integer',
            'has_customer_segmentation' => 'boolean',
            'has_service_based_targeting' => 'boolean',
            'has_high_value_targeting' => 'boolean',
            'has_advanced_insights' => 'boolean',
            'has_upsell_recommendations' => 'string|in:none,basic,advanced',
            'has_cross_sell_recommendations' => 'string|in:none,basic,advanced',
            'has_priority_visibility' => 'boolean',
            'is_active' => 'boolean',
        ]);

        $validated['created_by'] = $request->user()->id ?? null;
        $plan = SubscriptionPlan::create($validated);

        return response()->json([
            'success' => true,
            'message' => 'Plan created successfully',
            'plan' => $plan
        ]);
    }

    /**
     * Update a specific master subscription plan.
     */
    public function update(Request $request, $id)
    {
        $plan = SubscriptionPlan::findOrFail($id);
        
        $validated = $request->validate([
            'name' => 'string|max:50',
            'price' => 'numeric',
            'whatsapp_campaign_limit' => 'integer',
            'has_customer_segmentation' => 'boolean',
            'has_service_based_targeting' => 'boolean',
            'has_high_value_targeting' => 'boolean',
            'has_advanced_insights' => 'boolean',
            'has_upsell_recommendations' => 'string|in:none,basic,advanced',
            'has_cross_sell_recommendations' => 'string|in:none,basic,advanced',
            'has_priority_visibility' => 'boolean',
            'is_active' => 'boolean',
        ]);

        $plan->update($validated);

        return response()->json([
            'success' => true,
            'message' => 'Plan updated successfully',
            'plan' => $plan
        ]);
    }

    /**
     * Delete a master subscription plan.
     */
    public function destroy($id)
    {
        $plan = SubscriptionPlan::findOrFail($id);
        
        // Ensure no active salons are using this plan before deletion
        if (SalonSubscription::where('plan_id', $id)->where('status', 'active')->exists()) {
            return response()->json([
                'success' => false,
                'message' => 'Cannot delete plan because active salons are subscribed to it.'
            ], 400);
        }

        $plan->delete();

        return response()->json([
            'success' => true,
            'message' => 'Plan deleted successfully'
        ]);
    }

    /**
     * Assign a plan (e.g. Commission overriding) to a specific salon.
     */
    public function assignToSalon(Request $request, $salonId)
    {
        $salon = Salon::findOrFail($salonId);
        
        $request->validate([
            'plan_id' => 'required|exists:subscription_plans,id',
            'billing_type' => 'required|in:flat,commission',
            'commission_percentage' => 'nullable|numeric|min:0|max:100',
            'feature_level' => 'required|in:starter,growth',
        ]);

        // Cancel previous active subscription if exists
        if ($salon->currentSubscription) {
            $salon->currentSubscription->update([
                'status' => 'cancelled',
                'cancelled_at' => Carbon::now()
            ]);
        }

        $plan = SubscriptionPlan::findOrFail($request->plan_id);

        $subscription = SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'feature_level' => $request->feature_level,
            'billing_type' => $request->billing_type,
            'commission_percentage' => $request->billing_type === 'commission' ? $request->commission_percentage : null,
            'plan_price_snapshot' => $plan->price,
            'start_date' => Carbon::now(),
            'end_date' => Carbon::now()->addMonth(),
            'status' => 'active',
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Subscription assigned to salon successfully',
            'subscription' => $subscription->load('plan')
        ]);
    }
}
