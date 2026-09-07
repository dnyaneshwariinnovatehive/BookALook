<?php

namespace App\Services;

use App\Models\Appointment;
use App\Models\Cart;
use App\Models\ProviderLeave;
use App\Models\ProviderWorkingHour;
use App\Models\SalonWorkingHour;
use App\Models\ServiceProvider;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Server-side availability engine.
 *
 * Everything the customer app greys out is decided here: salon general hours,
 * salon closures, provider shifts / weekly off / breaks, approved leaves and
 * existing appointments of the same provider.
 */
class AvailabilityService
{
    /** Booking grid granularity, in minutes. */
    public const SLOT_MINUTES = 30;

    /** Advance % used when neither the service nor the combo defines one. */
    public const DEFAULT_ADVANCE_PERCENTAGE = 25.0;

    /**
     * Flatten a cart into what the availability engine needs:
     * the distinct services that must be performed, the total duration and money.
     *
     * @return array{service_ids: string[], duration: int, total: float, advance: float}
     */
    public function summariseCart(Cart $cart): array
    {
        $serviceIds = [];
        $duration = 0;
        $total = 0.0;
        $advance = 0.0;

        foreach ($cart->items as $item) {
            $quantity = max(1, (int) $item->quantity);

            if ($item->service) {
                $serviceIds[] = $item->service_id;
                $duration += $this->serviceDuration($item->service) * $quantity;

                $price = (float) $item->service->price * $quantity;
                $total += $price;
                $advance += $price * $this->advancePercentage($item->service->advance_percentage) / 100;
                continue;
            }

            if ($item->combo) {
                $comboPrice = 0.0;
                foreach ($item->combo->services as $service) {
                    $serviceIds[] = $service->id;
                    $duration += $this->serviceDuration($service) * $quantity;
                    $comboPrice += (float) ($service->pivot->combo_special_price ?? $service->price) * $quantity;
                }

                $total += $comboPrice;
                $advance += $comboPrice * $this->advancePercentage($item->combo->advance_percentage) / 100;
            }
        }

        return [
            'service_ids' => array_values(array_unique($serviceIds)),
            'duration' => max($duration, self::SLOT_MINUTES),
            'total' => round($total, 2),
            'advance' => round(min($advance, $total), 2),
        ];
    }

    /**
     * The same summary for an already-booked appointment, read from the
     * snapshotted appointment_services lines. Used when rescheduling.
     *
     * @return array{service_ids: string[], duration: int, total: float, advance: float}
     */
    public function summariseAppointment(Appointment $appointment): array
    {
        $lines = $appointment->services->where('line_status', '!=', 'cancelled');

        return [
            'service_ids' => $lines->pluck('service_id')->unique()->values()->all(),
            'duration' => max((int) $lines->sum('duration_minutes_at_booking'), self::SLOT_MINUTES),
            'total' => (float) $appointment->total_amount,
            'advance' => (float) $appointment->advance_amount,
        ];
    }

    /**
     * Every active provider of the salon, flagged with whether they can perform
     * the whole basket. Ineligible providers are returned too so the app can
     * grey them out instead of hiding them.
     *
     * @param  string[]  $requiredServiceIds
     */
    public function providersForSalon(string $salonId, array $requiredServiceIds): array
    {
        $providers = ServiceProvider::with(['user:id,name', 'services:id'])
            ->where('salon_id', $salonId)
            ->where('is_active', true)
            ->get();

        $serviceNames = $this->serviceNames($requiredServiceIds);

        return $providers->map(function (ServiceProvider $provider) use ($requiredServiceIds, $serviceNames) {
            $offered = $provider->services->pluck('id')->all();
            $missing = array_values(array_diff($requiredServiceIds, $offered));

            return [
                'id' => $provider->id,
                'name' => $provider->user->name ?? 'Staff',
                'specialization' => $provider->specialization,
                'is_eligible' => empty($missing),
                'missing_service_ids' => $missing,
                'missing_service_names' => array_values(array_map(
                    fn ($id) => $serviceNames[$id] ?? 'this service',
                    $missing
                )),
            ];
        })->all();
    }

    /**
     * Build the 30-minute grid for a date, marking each block available or not.
     *
     * @param  string[]  $providerIds  Candidates. One entry = a specific provider,
     *                                 many entries = "Any Available" (a block is
     *                                 open if at least one of them is free).
     * @return array{closed: bool, reason: ?string, slots: array<int, array>}
     */
    public function generateSlots(
        string $salonId,
        string $date,
        array $providerIds,
        int $durationMinutes,
        ?string $ignoreAppointmentId = null
    ): array {
        $day = Carbon::parse($date)->dayOfWeek; // 0 = Sunday ... 6 = Saturday

        $salonHours = SalonWorkingHour::where('salon_id', $salonId)
            ->where('day_of_week', $day)
            ->first();

        if (! $salonHours || $salonHours->is_closed) {
            return $this->closed('The salon is closed on this day.');
        }

        $salonOpen = $this->toMinutes($salonHours->open_time);
        $salonClose = $this->toMinutes($salonHours->close_time);

        if ($salonOpen === null || $salonClose === null || $salonClose <= $salonOpen) {
            return $this->closed('The salon has not published hours for this day.');
        }

        // A re-opened closure no longer blocks the day.
        $isClosureDay = DB::table('salon_closures')
            ->where('salon_id', $salonId)
            ->whereDate('closed_date', $date)
            ->whereNull('reopened_at')
            ->exists();

        if ($isClosureDay) {
            return $this->closed('The salon is closed on this date.');
        }

        if (empty($providerIds)) {
            return $this->closed('No service provider can perform all the selected services.');
        }

        $schedules = [];
        foreach ($providerIds as $providerId) {
            $schedules[$providerId] = $this->providerSchedule($providerId, $date, $day, $ignoreAppointmentId);
        }

        // Today's slots that have already started are not bookable.
        $earliestStart = Carbon::parse($date)->isToday()
            ? Carbon::now()->hour * 60 + Carbon::now()->minute
            : -1;

        $slots = [];
        for ($start = $salonOpen; $start + self::SLOT_MINUTES <= $salonClose; $start += self::SLOT_MINUTES) {
            $end = $start + $durationMinutes;

            $reason = null;
            $freeProviderIds = [];

            if ($start <= $earliestStart) {
                $reason = 'past';
            } elseif ($end > $salonClose) {
                $reason = 'salon_closing';
            } else {
                foreach ($schedules as $providerId => $schedule) {
                    $blockedBy = $this->blockReason($schedule, $start, $end);
                    if ($blockedBy === null) {
                        $freeProviderIds[] = $providerId;
                    } elseif ($reason === null) {
                        $reason = $blockedBy;
                    }
                }

                if (! empty($freeProviderIds)) {
                    $reason = null;
                }
            }

            $slots[] = [
                'time' => $this->toClock($start),
                'end_time' => $this->toClock(min($end, 24 * 60)),
                'available' => $reason === null,
                'reason' => $reason,
                'available_provider_ids' => $freeProviderIds,
            ];
        }

        return ['closed' => false, 'reason' => null, 'slots' => $slots];
    }

    /**
     * Re-check a single slot at booking time and resolve which provider takes it.
     * Returns the provider id, or null when the slot is no longer bookable.
     *
     * @param  string[]  $providerIds
     */
    public function resolveProviderForSlot(
        string $salonId,
        string $date,
        string $time,
        array $providerIds,
        int $durationMinutes,
        ?string $ignoreAppointmentId = null
    ): ?string {
        $result = $this->generateSlots($salonId, $date, $providerIds, $durationMinutes, $ignoreAppointmentId);

        foreach ($result['slots'] as $slot) {
            if ($slot['time'] === $time && $slot['available']) {
                return $slot['available_provider_ids'][0] ?? null;
            }
        }

        return null;
    }

    /**
     * Busy intervals + shift window for one provider on one date.
     *
     * @return array{off: bool, reason: ?string, shift: ?array{0: int, 1: int}, busy: array<int, array{0: int, 1: int, 2: string}>}
     */
    private function providerSchedule(string $providerId, string $date, int $day, ?string $ignoreAppointmentId): array
    {
        $hours = ProviderWorkingHour::where('provider_id', $providerId)
            ->where('day_of_week', $day)
            ->first();

        if (! $hours || $hours->is_weekly_off) {
            return ['off' => true, 'reason' => 'provider_off', 'shift' => null, 'busy' => []];
        }

        $shiftStart = $this->toMinutes($hours->shift_start);
        $shiftEnd = $this->toMinutes($hours->shift_end);

        if ($shiftStart === null || $shiftEnd === null || $shiftEnd <= $shiftStart) {
            return ['off' => true, 'reason' => 'provider_off', 'shift' => null, 'busy' => []];
        }

        $busy = [];

        $breakStart = $this->toMinutes($hours->break_start);
        $breakEnd = $this->toMinutes($hours->break_end);
        if ($breakStart !== null && $breakEnd !== null && $breakEnd > $breakStart) {
            $busy[] = [$breakStart, $breakEnd, 'break'];
        }

        $leaves = ProviderLeave::where('provider_id', $providerId)
            ->whereDate('leave_date', $date)
            ->where('status', 'approved')
            ->get();

        foreach ($leaves as $leave) {
            if ($leave->is_full_day) {
                return ['off' => true, 'reason' => 'on_leave', 'shift' => null, 'busy' => []];
            }

            $from = $this->toMinutes($leave->start_time);
            $to = $this->toMinutes($leave->end_time);
            if ($from !== null && $to !== null && $to > $from) {
                $busy[] = [$from, $to, 'on_leave'];
            }
        }

        // Only statuses that actually hold the chair block a slot. A booking
        // released by an emergency closure has given its time back, so the
        // freed-up slot must be offered to everyone — including the customer
        // who is rebooking it.
        $appointments = Appointment::where('appointed_provider_id', $providerId)
            ->whereDate('appointment_date', $date)
            ->whereIn('status', BookingPolicyService::BLOCKING_STATUSES)
            ->when($ignoreAppointmentId, fn ($q) => $q->where('id', '!=', $ignoreAppointmentId))
            ->get(['start_time', 'end_time']);

        foreach ($appointments as $appointment) {
            $from = $this->toMinutes($appointment->start_time);
            $to = $this->toMinutes($appointment->end_time);
            if ($from !== null && $to !== null && $to > $from) {
                $busy[] = [$from, $to, 'booked'];
            }
        }

        return ['off' => false, 'reason' => null, 'shift' => [$shiftStart, $shiftEnd], 'busy' => $busy];
    }

    /**
     * Why this provider cannot take [$start, $end), or null when they can.
     */
    private function blockReason(array $schedule, int $start, int $end): ?string
    {
        if ($schedule['off']) {
            return $schedule['reason'];
        }

        [$shiftStart, $shiftEnd] = $schedule['shift'];
        if ($start < $shiftStart || $end > $shiftEnd) {
            return 'outside_shift';
        }

        foreach ($schedule['busy'] as [$busyStart, $busyEnd, $reason]) {
            if ($start < $busyEnd && $busyStart < $end) {
                return $reason;
            }
        }

        return null;
    }

    private function closed(string $reason): array
    {
        return ['closed' => true, 'reason' => $reason, 'slots' => []];
    }

    private function serviceDuration($service): int
    {
        return (int) ($service->template->estimated_duration_minutes ?? self::SLOT_MINUTES);
    }

    private function advancePercentage($value): float
    {
        return $value === null ? self::DEFAULT_ADVANCE_PERCENTAGE : (float) $value;
    }

    /**
     * @param  string[]  $serviceIds
     * @return array<string, string>
     */
    private function serviceNames(array $serviceIds): array
    {
        if (empty($serviceIds)) {
            return [];
        }

        return DB::table('services')
            ->join('service_templates', 'service_templates.id', '=', 'services.template_id')
            ->whereIn('services.id', $serviceIds)
            ->pluck('service_templates.name', 'services.id')
            ->all();
    }

    private function toMinutes($time): ?int
    {
        if ($time === null || $time === '') {
            return null;
        }

        $parts = explode(':', (string) $time);
        if (count($parts) < 2) {
            return null;
        }

        return ((int) $parts[0]) * 60 + (int) $parts[1];
    }

    private function toClock(int $minutes): string
    {
        return sprintf('%02d:%02d', intdiv($minutes, 60), $minutes % 60);
    }
}
