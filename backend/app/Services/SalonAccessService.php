<?php

namespace App\Services;

use App\Models\Salon;
use App\Models\SalonSubscription;
use Carbon\Carbon;

/**
 * Whether a salon is trading.
 *
 * One place decides this, because three surfaces depend on the same answer: the
 * customer app hides an unserviceable salon, the partner app locks itself, and
 * the API refuses the work. If they disagreed, a salon could take bookings it
 * has not paid to receive.
 *
 * A subscription that has run out is expired on read rather than waiting for
 * the nightly job, so the answer is never a day stale.
 */
class SalonAccessService
{
    public const REASON_SUSPENDED = 'suspended';
    public const REASON_NOT_APPROVED = 'not_approved';
    public const REASON_NO_SUBSCRIPTION = 'no_subscription';
    public const REASON_SUBSCRIPTION_EXPIRED = 'subscription_expired';

    /**
     * @return array{
     *   is_active: bool, reason: ?string, message: ?string,
     *   subscription: ?SalonSubscription, expired_on: ?string, days_remaining: ?int
     * }
     */
    public function status(Salon $salon): array
    {
        $this->expireStale($salon->id);

        if ($salon->status === 'suspended') {
            return $this->blocked(self::REASON_SUSPENDED, 'This salon is temporarily unavailable.');
        }

        if ($salon->status !== 'active') {
            return $this->blocked(self::REASON_NOT_APPROVED, 'This salon is not accepting online bookings yet.');
        }

        $subscription = SalonSubscription::with('plan')
            ->where('salon_id', $salon->id)
            ->where('status', 'active')
            ->latest('start_date')
            ->first();

        if (! $subscription) {
            // Either never subscribed, or the last plan lapsed.
            $lapsed = SalonSubscription::where('salon_id', $salon->id)
                ->orderByDesc('end_date')
                ->first();

            return $this->blocked(
                $lapsed ? self::REASON_SUBSCRIPTION_EXPIRED : self::REASON_NO_SUBSCRIPTION,
                'This salon is not taking online bookings at the moment.',
                expiredOn: $lapsed ? Carbon::parse($lapsed->end_date)->toDateString() : null,
            );
        }

        return [
            'is_active' => true,
            'reason' => null,
            'message' => null,
            'subscription' => $subscription,
            'expired_on' => null,
            'days_remaining' => (int) Carbon::today()->diffInDays(Carbon::parse($subscription->end_date), false),
        ];
    }

    /** Convenience for callers that only have an id. */
    public function statusForId(string $salonId): array
    {
        $salon = Salon::find($salonId);

        return $salon
            ? $this->status($salon)
            : $this->blocked(self::REASON_NOT_APPROVED, 'Salon not found.');
    }

    public function isActive(string $salonId): bool
    {
        return $this->statusForId($salonId)['is_active'];
    }

    /**
     * What the partner app needs to draw its lock screen: why it is locked, and
     * who to chase about it.
     */
    public function partnerPayload(Salon $salon): array
    {
        $status = $this->status($salon);
        $subscription = $status['subscription'];
        $admin = $salon->admin;

        return [
            'salon_id' => $salon->id,
            'salon_name' => $salon->name,
            'is_locked' => ! $status['is_active'],
            'reason' => $status['reason'],
            'expired_on' => $status['expired_on'],
            'days_remaining' => $status['days_remaining'],
            'subscription' => $subscription ? [
                'plan_name' => $subscription->plan->name ?? 'Plan',
                'billing_type' => $subscription->billing_type,
                'end_date' => Carbon::parse($subscription->end_date)->toDateString(),
            ] : null,
            // A staff member cannot renew — they can only ask the owner to,
            // so the owner's number is part of the answer.
            'salon_admin' => $admin ? [
                'name' => $admin->name,
                'phone' => $admin->phone,
            ] : null,
        ];
    }

    /**
     * Flip subscriptions whose end date has passed. Cheap, and it keeps every
     * read honest between scheduled runs.
     */
    public function expireStale(?string $salonId = null): int
    {
        return SalonSubscription::where('status', 'active')
            ->whereDate('end_date', '<', Carbon::today())
            ->when($salonId, fn ($q) => $q->where('salon_id', $salonId))
            ->update(['status' => 'expired']);
    }

    private function blocked(string $reason, string $message, ?string $expiredOn = null): array
    {
        return [
            'is_active' => false,
            'reason' => $reason,
            'message' => $message,
            'subscription' => null,
            'expired_on' => $expiredOn,
            'days_remaining' => null,
        ];
    }
}
