<?php

namespace App\Http\Middleware;

use App\Models\ServiceProvider;
use App\Services\SalonAccessService;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Closes a salon's features when its plan has lapsed.
 *
 * The partner app draws a lock screen, but that is only paint — anyone with the
 * API could carry on working. This is the actual gate, so an unpaid salon
 * cannot take a walk-in, check a customer in or collect money.
 *
 * Deliberately not applied to renewal, wallet or the access check itself: a
 * salon that cannot reach the renew button can never get out of the lock.
 */
class EnsureSalonSubscriptionActive
{
    public function __construct(private SalonAccessService $access)
    {
    }

    public function handle(Request $request, Closure $next): Response
    {
        $salonId = $request->route('salon_id') ?? $this->salonForCurrentUser($request);

        if (! $salonId) {
            return $next($request);
        }

        $status = $this->access->statusForId($salonId);

        if ($status['is_active']) {
            return $next($request);
        }

        // 402: the work is understood and permitted, but not paid for.
        return response()->json([
            'message' => match ($status['reason']) {
                // Postpaid: nothing has been bought, so there is nothing to renew.
                SalonAccessService::REASON_COMMISSION_UNSETTLED
                    => 'This salon has an unsettled commission month. It will go back online once the payout is settled.',
                SalonAccessService::REASON_SUBSCRIPTION_EXPIRED,
                SalonAccessService::REASON_NO_SUBSCRIPTION
                    => 'This salon\'s subscription plan has lapsed. Renew the plan to use the app again.',
                default => $status['message'],
            },
            'subscription_required' => true,
            'reason' => $status['reason'],
            'billing_model' => $status['billing_model'],
            'expired_on' => $status['expired_on'],
        ], 402);
    }

    /**
     * Routes without a salon in the path still belong to one — a staff member
     * only ever works at a single salon.
     */
    private function salonForCurrentUser(Request $request): ?string
    {
        $user = $request->user();

        if (! $user || $user->role !== 'service_provider') {
            return null;
        }

        return ServiceProvider::where('user_id', $user->id)->value('salon_id');
    }
}
