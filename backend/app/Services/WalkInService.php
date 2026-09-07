<?php

namespace App\Services;

use App\Models\Appointment;
use App\Models\AppointmentService as AppointmentLine;
use App\Models\Service;
use App\Models\ServiceProvider;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Customers who walk in off the street.
 *
 * The important difference from an app booking is that nothing was agreed in
 * advance: there is no cart, no advance payment and no chosen staff member.
 * Whoever is at the desk picks the services and the person doing the work, and
 * the whole amount is collected at the counter afterwards through the normal
 * billing flow.
 */
class WalkInService
{
    /** Fallback when a service template has no duration recorded. */
    public const DEFAULT_DURATION_MINUTES = 30;

    /**
     * The salon's live catalogue, flat and priced, plus who can work on it.
     *
     * Deliberately not the grouped shape the services tab uses — the desk needs
     * a searchable list with prices and durations, not a category tree.
     *
     * @return array{services: array, providers: array}
     */
    public function options(string $salonId): array
    {
        $services = Service::with('template.category')
            ->where('salon_id', $salonId)
            ->where('is_active', true)
            ->get()
            ->map(fn (Service $service) => [
                'id' => $service->id,
                'name' => $service->template->name ?? 'Service',
                'category' => $service->template->category->name ?? 'Other',
                'price' => (float) $service->price,
                'duration_minutes' => (int) ($service->template->estimated_duration_minutes
                    ?? self::DEFAULT_DURATION_MINUTES),
                'gender_focus' => $service->gender_focus,
            ])
            ->sortBy([['category', 'asc'], ['name', 'asc']])
            ->values()
            ->all();

        $providers = ServiceProvider::with(['user:id,name', 'services:id'])
            ->where('salon_id', $salonId)
            ->where('is_active', true)
            ->get()
            ->map(fn (ServiceProvider $provider) => [
                'id' => $provider->id,
                'name' => $provider->user->name ?? 'Staff',
                'specialization' => $provider->specialization,
                // Lets the desk see at a glance who is trained on what.
                'service_ids' => $provider->services->pluck('id')->all(),
            ])
            ->sortBy('name')
            ->values()
            ->all();

        return ['services' => $services, 'providers' => $providers];
    }

    /**
     * Price and time the chosen basket, using the same snapshot rules a booked
     * appointment uses.
     *
     * @param  \Illuminate\Support\Collection<int, Service>  $services
     * @return array{total: float, duration: int}
     */
    public function summarise($services): array
    {
        $total = 0.0;
        $duration = 0;

        foreach ($services as $service) {
            $total += (float) $service->price;
            $duration += (int) ($service->template->estimated_duration_minutes
                ?? self::DEFAULT_DURATION_MINUTES);
        }

        return [
            'total' => round($total, 2),
            'duration' => max($duration, self::DEFAULT_DURATION_MINUTES),
        ];
    }

    /**
     * Appointments already on this provider's diary that overlap the proposed
     * window. Returned rather than thrown so the desk can decide: squeezing
     * someone in is a normal thing for a salon to do, but it should be a choice.
     *
     * @return array<int, array>
     */
    public function conflictsFor(
        string $providerId,
        Carbon $start,
        Carbon $end,
        ?string $ignoreAppointmentId = null
    ): array {
        return Appointment::with('customer:id,name')
            ->where('appointed_provider_id', $providerId)
            ->whereDate('appointment_date', $start->toDateString())
            ->whereIn('status', BookingPolicyService::BLOCKING_STATUSES)
            ->when($ignoreAppointmentId, fn ($q) => $q->whereKeyNot($ignoreAppointmentId))
            // Half-open overlap: a booking ending exactly at our start is fine.
            ->where('start_time', '<', $end->format('H:i:s'))
            ->where('end_time', '>', $start->format('H:i:s'))
            ->orderBy('start_time')
            ->get()
            ->map(fn (Appointment $a) => [
                'id' => $a->id,
                'start_time' => substr($a->start_time, 0, 5),
                'end_time' => substr($a->end_time, 0, 5),
                'customer_name' => $a->customer->name ?? $a->walk_in_customer_name ?? 'Customer',
                'status' => $a->status,
            ])
            ->all();
    }

    /**
     * Create the walk-in.
     *
     * Starting now puts it straight into `in_progress` under the chosen staff
     * member — there is no QR to scan for someone standing at the desk. Booking
     * it for later leaves it `scheduled`, so it behaves like any other booking
     * and gets checked in when they arrive.
     *
     * @param  string[]  $serviceIds
     */
    public function create(
        string $salonId,
        array $serviceIds,
        string $providerId,
        array $customer,
        ?Carbon $startAt,
        string $actorId
    ): Appointment {
        $services = Service::with('template')
            ->where('salon_id', $salonId)
            ->whereIn('id', $serviceIds)
            ->get();

        $summary = $this->summarise($services);

        $startsNow = $startAt === null;
        $start = $startAt ?? now();
        $end = (clone $start)->addMinutes($summary['duration']);

        return DB::transaction(function () use (
            $salonId, $services, $summary, $providerId, $customer, $start, $end, $startsNow, $actorId
        ) {
            $appointment = Appointment::create([
                'salon_id' => $salonId,
                'customer_id' => null,
                'appointed_provider_id' => $providerId,
                // Nobody is serving a booking that has not started yet.
                'serving_provider_id' => $startsNow ? $providerId : null,
                'booking_source' => 'walk_in',
                'walk_in_customer_name' => $customer['name'],
                'walk_in_customer_phone' => $customer['phone'] ?? null,
                'walk_in_customer_gender' => $customer['gender'] ?? null,
                'appointment_date' => $start->toDateString(),
                'start_time' => $start->format('H:i:s'),
                'end_time' => $end->format('H:i:s'),
                'status' => $startsNow ? 'in_progress' : 'scheduled',
                'payment_option' => 'full_at_venue',
                'total_amount' => $summary['total'],
                'advance_amount' => 0,
                'balance_amount' => $summary['total'],
                'started_at' => $startsNow ? now() : null,
                // A person at the desk is the verification.
                'verification_method' => $startsNow
                    ? AppointmentCheckInService::VERIFY_MANUAL
                    : 'qr',
                'manual_check_in_reason' => $startsNow ? 'Walk-in added at the salon' : null,
                'qr_verified_by' => $startsNow ? $actorId : null,
                'qr_verified_at' => $startsNow ? now() : null,
            ]);

            foreach ($services as $service) {
                AppointmentLine::create([
                    'appointment_id' => $appointment->id,
                    'service_id' => $service->id,
                    'serving_provider_id' => $startsNow ? $providerId : null,
                    'price_at_booking' => $service->price,
                    'original_service_price' => $service->price,
                    'duration_minutes_at_booking' => $service->template->estimated_duration_minutes
                        ?? self::DEFAULT_DURATION_MINUTES,
                    // 'booked' is the vocabulary the rest of the system uses for
                    // a live line; appointment status lives on the appointment.
                    'line_status' => 'booked',
                ]);
            }

            return $appointment;
        });
    }
}
