<?php

namespace App\Services;

use App\Models\Appointment;
use App\Models\PlatformPolicySetting;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * The customer-facing rules around an existing booking: how late it can be
 * cancelled or rescheduled, how much advance comes back, whether the salon
 * closed the day, and the same-day change abuse penalty.
 *
 * All configurable numbers come from platform_policy_settings, which SuperAdmin
 * owns. See PlatformPolicySetting::DEFAULTS for the starting values.
 */
class BookingPolicyService
{
    /** Statuses that still count as a live, changeable booking. */
    public const ACTIVE_STATUSES = ['scheduled', 'confirmed', 'pending_payment'];

    /** Statuses that close a booking for good — these always belong to history. */
    public const TERMINAL_STATUSES = ['completed', 'cancelled', 'no_show', 'rescheduled'];

    /**
     * Which tab a booking belongs to.
     *
     * Upcoming = anything not yet finished, dated today or later. A booking
     * whose start time has passed but which the salon has not completed stays
     * in Upcoming for the rest of the day, rather than disappearing into
     * history while the customer is still expecting to be served.
     */
    public function isUpcoming(Appointment $appointment): bool
    {
        if (in_array($appointment->status, self::TERMINAL_STATUSES, true)) {
            return false;
        }

        return ! Carbon::parse($appointment->appointment_date)->startOfDay()->isBefore(Carbon::today());
    }

    public function cancellationCutoffMinutes(): int
    {
        return (int) PlatformPolicySetting::value('cancellation_cutoff_minutes');
    }

    public function rescheduleCutoffMinutes(): int
    {
        return (int) PlatformPolicySetting::value('reschedule_cutoff_minutes');
    }

    public function abuseThreshold(): int
    {
        return (int) PlatformPolicySetting::value('same_day_change_abuse_threshold');
    }

    public function startsAt(Appointment $appointment): Carbon
    {
        return Carbon::parse(
            Carbon::parse($appointment->appointment_date)->format('Y-m-d') . ' ' . $appointment->start_time
        );
    }

    /**
     * Has the salon announced a closure for this appointment's date? That
     * entitles the customer to a free-of-cost reschedule, cutoff waived.
     */
    public function isSalonClosedOn(string $salonId, string $date): bool
    {
        return DB::table('salon_closures')
            ->where('salon_id', $salonId)
            ->whereDate('closed_date', $date)
            ->exists();
    }

    private function baseWindow(Appointment $appointment, int $cutoff): array
    {
        $freeReschedule = $this->isSalonClosedOn(
            $appointment->salon_id,
            Carbon::parse($appointment->appointment_date)->format('Y-m-d')
        );

        $base = ['cutoff_minutes' => $cutoff, 'free_reschedule' => $freeReschedule];

        if (! in_array($appointment->status, self::ACTIVE_STATUSES, true)) {
            return $base + [
                'allowed' => false,
                'reason' => 'This appointment is already ' . str_replace('_', ' ', $appointment->status) . '.',
            ];
        }

        if ($freeReschedule) {
            return $base + ['allowed' => true, 'reason' => null];
        }

        if ($this->startsAt($appointment)->isPast()) {
            return $base + ['allowed' => false, 'reason' => 'This appointment has already started.'];
        }

        if (now()->addMinutes($cutoff)->greaterThan($this->startsAt($appointment))) {
            return $base + [
                'allowed' => false,
                'reason' => "Changes are not allowed within {$cutoff} minutes of the appointment.",
            ];
        }

        return $base + ['allowed' => true, 'reason' => null];
    }

    public function cancellationWindow(Appointment $appointment): array
    {
        return $this->baseWindow($appointment, $this->cancellationCutoffMinutes());
    }

    public function rescheduleWindow(Appointment $appointment): array
    {
        return $this->baseWindow($appointment, $this->rescheduleCutoffMinutes());
    }

    /**
     * How much of the paid advance comes back, following each service's own
     * will_refund_advance_if_cancelled flag (combo lines follow the combo's).
     *
     * @return array{refundable: float, forfeited: float, refundable_service_names: string[]}
     */
    public function refundBreakdown(Appointment $appointment): array
    {
        $refundable = 0.0;
        $forfeited = 0.0;
        $names = [];

        $lines = $appointment->services->where('line_status', '!=', 'cancelled');
        $lineTotal = (float) $lines->sum('price_at_booking');
        $advancePaid = (float) $appointment->advance_amount;

        foreach ($lines as $line) {
            // Split the advance across lines in proportion to their price, so a
            // partly-refundable basket refunds only its refundable share.
            $share = $lineTotal > 0
                ? $advancePaid * ((float) $line->price_at_booking / $lineTotal)
                : 0.0;

            $refunds = $line->combo_id
                ? (bool) ($line->combo->will_refund_advance_if_cancelled ?? false)
                : (bool) ($line->service->will_refund_advance_if_cancelled ?? false);

            if ($refunds) {
                $refundable += $share;
                $names[] = $line->service->template->name ?? 'Service';
            } else {
                $forfeited += $share;
            }
        }

        return [
            'refundable' => round($refundable, 2),
            'forfeited' => round($forfeited, 2),
            'refundable_service_names' => array_values(array_unique($names)),
        ];
    }

    /**
     * How many times this customer has already cancelled or rescheduled a
     * booking that was due on $date.
     */
    public function sameDayChangeCount(string $customerId, string $date): int
    {
        return Appointment::where('customer_id', $customerId)
            ->whereDate('appointment_date', $date)
            ->where(function ($q) {
                $q->where(function ($q) {
                    $q->where('status', 'cancelled')->where('cancelled_by', 'customer');
                })->orWhere('status', 'rescheduled');
            })
            ->count();
    }

    /**
     * Past the abuse threshold, advance-only no longer applies for that date —
     * the customer must pay the full amount upfront.
     *
     * @return array{full_upfront: bool, changes_used: int, threshold: int}
     */
    public function paymentRequirement(string $customerId, string $date): array
    {
        $threshold = $this->abuseThreshold();
        $used = $this->sameDayChangeCount($customerId, $date);

        return [
            'full_upfront' => $used >= $threshold,
            'changes_used' => $used,
            'threshold' => $threshold,
        ];
    }
}
