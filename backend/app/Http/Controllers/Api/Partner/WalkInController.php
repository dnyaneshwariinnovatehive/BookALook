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
use Illuminate\Support\Facades\DB;
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

        $provider = ServiceProvider::with('services:id')
            ->where('id', $providerId)
            ->where('salon_id', $salonId)
            ->where('is_active', true)
            ->first();

        if (! $provider) {
            return response()->json(['message' => 'That staff member does not work at this salon.'], 422);
        }

        // Every service has to belong to this salon — an id from another salon
        // would otherwise be priced onto this salon's bill.
        $uniqueServices = \App\Models\Service::with('template')
            ->where('salon_id', $salonId)
            ->whereIn('id', $request->services)
            ->get()
            ->keyBy('id');

        if ($uniqueServices->count() !== count(array_unique($request->services))) {
            return response()->json(['message' => 'One or more services are not offered by this salon.'], 422);
        }

        $providerServiceIds = $provider->services->pluck('id')->toArray();
        $missingServices = array_diff(array_unique($request->services), $providerServiceIds);

        if (!empty($missingServices)) {
            return response()->json(['message' => 'That staff member cannot perform all the selected services.'], 422);
        }

        $services = collect($request->services)->map(fn ($id) => $uniqueServices[$id]);

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

        $uniqueServices = \App\Models\Service::with('template')
            ->where('salon_id', $salonId)
            ->whereIn('id', $request->services)
            ->get()
            ->keyBy('id');

        if ($uniqueServices->count() !== count(array_unique($request->services))) {
            return response()->json(['message' => 'One or more services are not offered by this salon.'], 422);
        }

        $services = collect($request->services)->map(fn ($id) => $uniqueServices[$id]);

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
     * Walk-in customers history and metrics.
     */
    public function history(Request $request, $salonId)
    {
        if ($denied = $this->denyUnlessSalonStaff($request, $salonId)) {
            return $denied;
        }

        $user = $request->user();
        $isProvider = $user->role === 'service_provider';
        $currentProviderId = $this->currentProviderId($request, $salonId);

        $baseQuery = Appointment::where('salon_id', $salonId)
            ->where(function ($q) {
                $q->whereIn('booking_source', ['walk_in', 'offline'])
                  ->orWhereNotNull('walk_in_customer_name');
            });

        // A staff member sees the walk-ins they were booked for or served,
        // never the whole salon's — whatever scope the app asks for. Only the
        // owner sees everyone's.
        if ($isProvider) {
            $baseQuery->where(function ($q) use ($currentProviderId) {
                $q->where('appointed_provider_id', $currentProviderId)
                  ->orWhere('serving_provider_id', $currentProviderId);
            });
        }

        // Summary metrics over what this viewer may see
        $summaryQuery = clone $baseQuery;

        $todayStr = Carbon::today()->toDateString();
        $totalWalkIns = (clone $summaryQuery)->count();
        $todayWalkIns = (clone $summaryQuery)->whereDate('appointment_date', $todayStr)->count();
        $inProgressWalkIns = (clone $summaryQuery)->where('status', 'in_progress')->count();
        $completedWalkIns = (clone $summaryQuery)->where('status', 'completed')->count();
        $totalRevenue = (float) (clone $summaryQuery)
            ->where('status', 'completed')
            ->sum(DB::raw('COALESCE(final_billed_amount, total_amount, 0)'));

        // Filter query
        $query = clone $baseQuery;

        // The owner can narrow to one staff member.
        if (! $isProvider && $request->filled('provider_id') && $request->provider_id !== 'all') {
            $pId = $request->provider_id;
            $query->where(function ($q) use ($pId) {
                $q->where('appointed_provider_id', $pId)
                  ->orWhere('serving_provider_id', $pId);
            });
        }

        // Date filter
        if ($request->filled('date') && $request->date !== 'all') {
            $date = strtolower($request->date);
            if ($date === 'today') {
                $query->whereDate('appointment_date', Carbon::today()->toDateString());
            } elseif ($date === 'yesterday') {
                $query->whereDate('appointment_date', Carbon::yesterday()->toDateString());
            } elseif ($date === 'this_week') {
                $query->whereBetween('appointment_date', [
                    Carbon::now()->startOfWeek()->toDateString(),
                    Carbon::now()->endOfWeek()->toDateString(),
                ]);
            } elseif ($date === 'this_month') {
                $query->whereBetween('appointment_date', [
                    Carbon::now()->startOfMonth()->toDateString(),
                    Carbon::now()->endOfMonth()->toDateString(),
                ]);
            } else {
                $query->whereDate('appointment_date', $request->date);
            }
        }

        // Status filter
        if ($request->filled('status') && $request->status !== 'all') {
            $query->where('status', strtolower($request->status));
        }

        // Search filter (customer name or phone)
        if ($request->filled('search')) {
            $term = trim($request->search);
            $query->where(function ($q) use ($term) {
                $q->where('walk_in_customer_name', 'like', "%{$term}%")
                  ->orWhere('walk_in_customer_phone', 'like', "%{$term}%");
            });
        }

        $perPage = (int) $request->input('per_page', 50);
        $appointments = $query->with([
                'appointedProvider.user:id,name,phone',
                'servingProvider.user:id,name,phone',
                'paymentCollector:id,name',
                // The invoices table calls it `total`. Asking for `total_amount`
                // made PostgreSQL reject the whole history request; SQLite
                // silently read the name as a string, so it only broke live.
                'invoice:id,appointment_id,invoice_number,total,pdf_url',
                'services.service.template.category:id,name',
                'services.servingProvider.user:id,name',
                'serviceAdditions.service.template:id,name,estimated_duration_minutes',
                'serviceAdditions.provider.user:id,name',
                'serviceAdditions.addedBy:id,name',
            ])
            ->orderBy('appointment_date', 'desc')
            ->orderBy('start_time', 'desc')
            ->paginate($perPage);

        $presented = $appointments->getCollection()->map(function (Appointment $a) {
            $services = $a->services->map(function ($s) {
                return [
                    'id' => $s->id,
                    'service_id' => $s->service_id,
                    'name' => $s->service?->template?->name ?? 'Service',
                    'category' => $s->service?->template?->category?->name ?? 'General',
                    'price' => (float) $s->price_at_booking,
                    'duration_minutes' => (int) $s->duration_minutes_at_booking,
                    'serving_provider_name' => $s->servingProvider?->user?->name ?? null,
                    'line_status' => $s->line_status,
                ];
            })->values()->all();

            $additions = $a->serviceAdditions->map(function ($add) {
                return [
                    'id' => $add->id,
                    'service_id' => $add->service_id,
                    'name' => $add->service?->template?->name ?? 'Additional Service',
                    'price' => (float) $add->price_at_addition,
                    'duration_minutes' => (int) $add->duration_minutes_at_addition,
                    'provider_name' => $add->provider?->user?->name ?? null,
                    'added_by_name' => $add->addedBy?->name ?? null,
                    'status' => $add->status,
                    'added_at' => $add->added_at ? Carbon::parse($add->added_at)->toIso8601String() : null,
                ];
            })->values()->all();

            return [
                'id' => $a->id,
                'status' => $a->status,
                'booking_source' => $a->booking_source,
                'appointment_date' => Carbon::parse($a->appointment_date)->toDateString(),
                'start_time' => substr($a->start_time, 0, 5),
                'end_time' => substr($a->end_time, 0, 5),
                'started_at' => $a->started_at ? Carbon::parse($a->started_at)->toIso8601String() : null,
                'completed_at' => $a->completed_at ? Carbon::parse($a->completed_at)->toIso8601String() : null,
                'customer_name' => $a->walk_in_customer_name ?? 'Walk-in Customer',
                'customer_phone' => $a->walk_in_customer_phone ?? '',
                'customer_gender' => $a->walk_in_customer_gender,
                'appointed_provider' => $a->appointedProvider ? [
                    'id' => $a->appointedProvider->id,
                    'name' => $a->appointedProvider->user?->name ?? 'Staff',
                    'phone' => $a->appointedProvider->user?->phone ?? null,
                ] : null,
                'serving_provider' => $a->servingProvider ? [
                    'id' => $a->servingProvider->id,
                    'name' => $a->servingProvider->user?->name ?? 'Staff',
                    'phone' => $a->servingProvider->user?->phone ?? null,
                ] : null,
                'services' => $services,
                'service_additions' => $additions,
                'total_amount' => (float) $a->total_amount,
                'advance_amount' => (float) $a->advance_amount,
                'balance_amount' => (float) $a->balance_amount,
                'final_billed_amount' => $a->final_billed_amount !== null ? (float) $a->final_billed_amount : null,
                'payment_mode' => $a->payment_mode,
                'payment_collected_at' => $a->payment_collected_at ? Carbon::parse($a->payment_collected_at)->toIso8601String() : null,
                'payment_collected_by_name' => $a->paymentCollector?->name ?? null,
                'verification_method' => $a->verification_method,
                'manual_check_in_reason' => $a->manual_check_in_reason,
                'invoice_id' => $a->invoice?->id ?? null,
                'invoice_number' => $a->invoice?->invoice_number ?? null,
            ];
        });

        return response()->json([
            'summary' => [
                'total_walk_ins' => $totalWalkIns,
                'today_walk_ins' => $todayWalkIns,
                'in_progress' => $inProgressWalkIns,
                'completed' => $completedWalkIns,
                'total_revenue' => round($totalRevenue, 2),
            ],
            'walk_ins' => $presented,
            'pagination' => [
                'current_page' => $appointments->currentPage(),
                'last_page' => $appointments->lastPage(),
                'per_page' => $appointments->perPage(),
                'total' => $appointments->total(),
            ],
            'viewer' => [
                'role' => $user->role,
                'provider_id' => $currentProviderId,
            ],
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
