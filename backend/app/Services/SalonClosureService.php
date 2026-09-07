<?php

namespace App\Services;

use App\Models\Appointment;
use App\Models\Salon;
use App\Models\SalonClosure;
use App\Services\Notifications\NotificationService;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Emergency closure of a whole trading day.
 *
 * Closing a day does two things at once: it stops new bookings landing on that
 * date (AvailabilityService reads salon_closures), and it releases every
 * booking already on it.
 *
 * Released bookings are NOT hard-cancelled. They move to `awaiting_reschedule`,
 * which keeps the service lines, the prices and the advance attached to the
 * same row. The customer picks a new slot for free and the money follows them;
 * if they would rather walk away they get the full advance back, because this
 * was the salon's doing and not theirs.
 */
class SalonClosureService
{
    /** Bookings a closure takes over. */
    public const RELEASABLE_STATUSES = ['pending_payment', 'scheduled', 'confirmed'];

    /**
     * Already under way or finished. An emergency at 3pm must not rewrite the
     * morning's completed work, so these are reported back as untouched.
     */
    public const UNTOUCHABLE_STATUSES = ['in_progress', 'completed'];

    public function __construct(
        private NotificationService $notifications,
        private BookingPolicyService $policy,
    ) {
    }

    /**
     * What closing [$date] would do, so the admin sees the blast radius before
     * confirming rather than after.
     *
     * @return array{date: string, already_closed: bool, affected_count: int,
     *               customer_count: int, walk_in_count: int, untouchable_count: int,
     *               advance_carried_forward: float, appointments: array<int, array>}
     */
    public function preview(string $salonId, string $date): array
    {
        $appointments = $this->releasableQuery($salonId, $date)->get();

        $untouchable = Appointment::where('salon_id', $salonId)
            ->whereDate('appointment_date', $date)
            ->whereIn('status', self::UNTOUCHABLE_STATUSES)
            ->count();

        return [
            'date' => $date,
            'already_closed' => $this->policy->isSalonClosedOn($salonId, $date),
            'affected_count' => $appointments->count(),
            'customer_count' => $appointments->pluck('customer_id')->filter()->unique()->count(),
            'walk_in_count' => $appointments->whereNull('customer_id')->count(),
            'untouchable_count' => $untouchable,
            'advance_carried_forward' => round((float) $appointments->sum('advance_amount'), 2),
            'appointments' => $appointments->map(fn (Appointment $a) => [
                'id' => $a->id,
                'start_time' => substr($a->start_time, 0, 5),
                'customer_name' => $a->customer->name ?? $a->walk_in_customer_name ?? 'Walk-in',
                'customer_phone' => $a->customer->phone ?? $a->walk_in_customer_phone,
                'is_walk_in' => $a->customer_id === null,
                'provider_name' => $a->appointedProvider->user->name ?? 'Any staff',
                'advance_paid' => (float) $a->advance_amount,
            ])->values()->all(),
        ];
    }

    /**
     * Close the day and release its bookings.
     *
     * Idempotent by design: re-running for a date that is already closed picks
     * up anything that slipped through (a booking made in the same second, a
     * half-finished earlier run) without touching what was already released.
     *
     * @return array{closure: SalonClosure, released: int, notified: int,
     *               untouchable_count: int, advance_carried_forward: float}
     */
    public function closeDay(string $salonId, string $date, ?string $reason, string $actorId): array
    {
        $salon = Salon::findOrFail($salonId);

        return DB::transaction(function () use ($salon, $date, $reason, $actorId) {
            // firstOrCreate keeps the unique (salon_id, closed_date) index happy
            // when a day is closed twice.
            $closure = SalonClosure::firstOrNew([
                'salon_id' => $salon->id,
                'closed_date' => $date,
            ]);

            $closure->fill([
                'reason' => $reason ?: $closure->reason,
                'triggers_mass_reschedule' => true,
                'created_by' => $closure->exists ? $closure->created_by : $actorId,
                'processed_by' => $actorId,
                'processed_at' => now(),
                'reschedule_processed' => true,
                // Closing a day that was previously re-opened puts it back in force.
                'reopened_at' => null,
                'reopened_by' => null,
            ])->save();

            // Locked so two admins hitting the button together cannot release
            // the same booking twice.
            $appointments = $this->releasableQuery($salon->id, $date)
                ->lockForUpdate()
                ->get();

            $dateLabel = Carbon::parse($date)->format('D, d M Y');
            $released = 0;
            $notified = 0;
            $carried = 0.0;

            foreach ($appointments as $appointment) {
                $appointment->status = 'awaiting_reschedule';
                $appointment->cancelled_by = 'salon';
                $appointment->cancelled_by_user_id = $actorId;
                $appointment->cancellation_reason = $reason ?: 'The salon is closed on this date.';
                $appointment->cancelled_at = now();
                $appointment->salon_closure_id = $closure->id;
                $appointment->save();

                // The lines stay 'booked' — they are copied onto the new
                // appointment when the customer picks a slot.
                $released++;
                $carried += (float) $appointment->advance_amount;

                if ($appointment->customer_id) {
                    $this->notifications->appointmentNeedsReschedule(
                        $appointment,
                        $salon->name ?? 'The salon',
                        $dateLabel,
                        $reason
                    );

                    $appointment->forceFill(['closure_notified_at' => now()])->save();
                    $notified++;
                }
            }

            return [
                'closure' => $closure->fresh(),
                'released' => $released,
                'notified' => $notified,
                'untouchable_count' => Appointment::where('salon_id', $salon->id)
                    ->whereDate('appointment_date', $date)
                    ->whereIn('status', self::UNTOUCHABLE_STATUSES)
                    ->count(),
                'advance_carried_forward' => round($carried, 2),
            ];
        });
    }

    /**
     * Re-open a previously closed day.
     *
     * The closure row is marked, never deleted. Bookings already released are
     * deliberately left alone: their customers have been told the day is off
     * and some will have rebooked elsewhere, so silently reinstating them would
     * double-book the salon. They keep the free reschedule they were promised,
     * which is exactly why the row has to survive.
     */
    public function reopenDay(SalonClosure $closure, string $actorId): int
    {
        $stillWaiting = $closure->appointments()
            ->where('status', 'awaiting_reschedule')
            ->count();

        $closure->forceFill([
            'reopened_at' => now(),
            'reopened_by' => $actorId,
            'triggers_mass_reschedule' => false,
        ])->save();

        return $stillWaiting;
    }

    /**
     * @return \Illuminate\Database\Eloquent\Builder<Appointment>
     */
    private function releasableQuery(string $salonId, string $date)
    {
        return Appointment::with(['customer:id,name,phone', 'appointedProvider.user:id,name'])
            ->where('salon_id', $salonId)
            ->whereDate('appointment_date', $date)
            ->whereIn('status', self::RELEASABLE_STATUSES)
            ->orderBy('start_time');
    }
}
