<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Salon;
use Illuminate\Support\Carbon;

class SubscriptionController extends Controller
{
    /**
     * Get active subscription details for the logged-in admin's salon.
     */
    public function getActiveSubscription(Request $request)
    {
        $user = $request->user();

        if ($user->role !== 'admin') {
            return response()->json(['success' => false, 'message' => 'Only admins can view billing'], 403);
        }

        $salon = Salon::where('admin_id', $user->id)->first();
        if (!$salon) {
            return response()->json(['success' => false, 'message' => 'Salon not found'], 404);
        }

        $subscription = $salon->currentSubscription()->with('plan')->first();

        if (!$subscription) {
            return response()->json([
                'success' => true,
                'has_subscription' => false,
                'message' => 'No active subscription found.'
            ]);
        }

        $daysRemaining = Carbon::now()->startOfDay()->diffInDays($subscription->end_date, false);

        return response()->json([
            'success' => true,
            'has_subscription' => true,
            'subscription' => $subscription,
            'days_remaining' => (int) $daysRemaining
        ]);
    }

    /**
     * Mock renew/upgrade endpoint.
     */
    public function renewSubscription(Request $request)
    {
        $user = $request->user();
        
        $salon = Salon::where('admin_id', $user->id)->first();
        if (!$salon || !$salon->currentSubscription) {
            return response()->json(['success' => false, 'message' => 'No active subscription to renew'], 404);
        }

        $subscription = $salon->currentSubscription;
        
        // Extend by 30 days
        $subscription->update([
            'end_date' => Carbon::parse($subscription->end_date)->addDays(30)
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Subscription successfully renewed for 30 days!',
            'new_expiry' => $subscription->end_date->format('Y-m-d')
        ]);
    }
}
