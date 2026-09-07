<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Services\AppointmentCheckInService;
use App\Services\WalkInService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

/**
 * Walk-in customers.
 *
 * Staff serve themselves; an admin at the desk serves anyone, which is why the
 * provider is an explicit choice here rather than "whoever is logged in".
 */
class WalkInController extends Controller
{
    public function __construct(
        private WalkInService $walkIns,
        private AppointmentCheckInService $checkIn,
    ) {
    }

    /**
     * The salon's priced catalogue and its staff, for the walk-in form.
     */
    public function options(Request $request, $salonId)
    {
        if ($denied = $this->denyUnlessSalonStaff($request, $salonId)) {
            return $denied;
        }

        $options = $this->walkIns->options($salonId);

        return response()->json($options + [
            // A provider adding their own walk-in should not have to pick
            // themselves out of a list.
            'default_provider_id' => $this->currentProviderId($request, $salonId),
            'can_choose_provider' => $request->user()->role !== 'service_provider',
        ]);
    }

    /**
     * Create a walk-in, either starting immediately or booked for later today.
     */
    public function store(Request $request, $salonId)
    {
        if ($denied = $this->denyUnlessSalonStaff($request, $salonId)) {
            return $denied;
        }

        $validator = Validator::make($request->all(), [
            'customer_name' => 'required|string|max:150',
            'customer_phone' => 'nullable|string|max:20',
            'gender' => 'nullable|in:Male,Female,Other',
            'services' => 'required|array|min:1',
            'services.*' => 'required|string|exists:services,id',
            'provider_id' => 'nullable|exists:service_providers,id',
            'start_time' => 'nullable|date_format:Y-m-d H:i:s',
            // Salons genuinely do squeeze people in; make it a decision, not an
            // accident.
            'allow_overlap' => 'boolean',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $providerId = $request->input('provider_id') ?? $this->currentProviderId($request, $salonId);

        if (! $providerId) {
            return response()->json([
                'message' => 'Choose which staff member is serving this customer.',
            ], 422);
        }

        if (! ServiceProvider::where('id', $providerId)
            ->where('salon_id', $salonId)
            ->where('is_active', true)
            ->exists()) {
            return response()->json(['message' => 'That staff member does not work at this salon.'], 422);
        }

        // Every service has to belong to this salon — an id from another salon
        // would otherwise be priced onto this salon's bill.
        $services = \App\Models\Service::with('template')
            ->where('salon_id', $salonId)
            ->whereIn('id', $request->services)
            ->get();

        if ($services->count() !== count(array_unique($request->services))) {
            return response()->json(['message' => 'One or more services are not offered by this salon.'], 422);
        }

        $startAt = $request->filled('start_time') ? Carbon::parse($request->start_time) : null;

        if ($startAt && $startAt->isPast() && ! $startAt->isToday()) {
            return response()->json(['message' => 'Pick a time today or later.'], 422);
        }

        $summary = $this->walkIns->summarise($services);
        $windowStart = $startAt ?? now();
        $windowEnd = (clone $windowStart)->addMinutes($summary['duration']);

        $conflicts = $this->walkIns->conflictsFor($providerId, $windowStart, $windowEnd);

        if ($conflicts && ! $request->boolean('allow_overlap')) {
            return response()->json([
                'message' => 'That staff member is already busy then.',
                'conflicts' => $conflicts,
                'can_override' => true,
            ], 409);
        }

        $appointment = $this->walkIns->create(
            $salonId,
            $services->pluck('id')->all(),
            $providerId,
            [
                'name' => $request->customer_name,
                'phone' => $request->customer_phone,
                'gender' => $request->gender,
            ],
            $startAt,
            $request->user()->id
        );

        $appointment->load($this->checkIn->relations());

        return response()->json([
            'message' => $startAt
                ? 'Walk-in booked for later today.'
                : 'Walk-in started.',
            'appointment' => $this->checkIn->present($appointment),
            'bill' => $this->checkIn->bill($appointment),
            'overlapped' => ! empty($conflicts),
        ], 201);
    }

    /**
     * Preview the price, duration and any clash before committing.
     */
    public function preview(Request $request, $salonId)
    {
        if ($denied = $this->denyUnlessSalonStaff($request, $salonId)) {
            return $denied;
        }

        $validator = Validator::make($request->all(), [
            'services' => 'required|array|min:1',
            'services.*' => 'required|string|exists:services,id',
            'provider_id' => 'nullable|exists:service_providers,id',
            'start_time' => 'nullable|date_format:Y-m-d H:i:s',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $services = \App\Models\Service::with('template')
            ->where('salon_id', $salonId)
            ->whereIn('id', $request->services)
            ->get();

        $summary = $this->walkIns->summarise($services);
        $start = $request->filled('start_time') ? Carbon::parse($request->start_time) : now();
        $end = (clone $start)->addMinutes($summary['duration']);

        $providerId = $request->input('provider_id') ?? $this->currentProviderId($request, $salonId);

        return response()->json([
            'total' => $summary['total'],
            'duration_minutes' => $summary['duration'],
            'starts_at' => $start->format('H:i'),
            'ends_at' => $end->format('H:i'),
            'conflicts' => $providerId
                ? $this->walkIns->conflictsFor($providerId, $start, $end)
                : [],
        ]);
    }

    /**
     * The ServiceProvider row for the caller, when they are one.
     */
    private function currentProviderId(Request $request, string $salonId): ?string
    {
        if ($request->user()->role !== 'service_provider') {
            return null;
        }

        return ServiceProvider::where('user_id', $request->user()->id)
            ->where('salon_id', $salonId)
            ->value('id');
    }

    /**
     * The salon's owner or one of its active staff. A walk-in creates a
     * billable appointment, so knowing a salon id is not enough.
     */
    private function denyUnlessSalonStaff(Request $request, string $salonId)
    {
        $user = $request->user();

        if ($user->role === 'superadmin') {
            return null;
        }

        if ($user->role === 'admin'
            && Salon::where('id', $salonId)->where('admin_id', $user->id)->exists()) {
            return null;
        }

        if ($user->role === 'service_provider'
            && ServiceProvider::where('user_id', $user->id)
                ->where('salon_id', $salonId)
                ->where('is_active', true)
                ->exists()) {
            return null;
        }

        return response()->json(['message' => 'You do not work at this salon.'], 403);
    }
}
