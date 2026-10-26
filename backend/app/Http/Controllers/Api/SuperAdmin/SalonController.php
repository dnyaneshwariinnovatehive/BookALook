<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use App\Models\AuditLog;
use App\Models\City;
use App\Models\Review;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\Service;
use App\Models\ServiceProvider;
use App\Models\SubArea;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Services\AuditLogger;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

class SalonController extends Controller
{
    /** Columns a table header is allowed to sort on. */
    private const SORTABLE = [
        'name', 'city', 'admin', 'collaborator', 'plan', 'status', 'created_at',
        'bookings', 'completed', 'revenue', 'rating', 'staff', 'services', 'last_booking',
    ];

    /**
     * Bookings that really happened or are coming. A slot held while the
     * customer pays is not one yet, and a rescheduled booking lives on as its
     * replacement — counting both would count the visit twice.
     */
    private const NOT_A_BOOKING = ['pending_payment', 'rescheduled'];

    /** A plan this close to its end is flagged as "expiring". */
    private const EXPIRING_DAYS = 5;

    public function index(Request $request)
    {
        $request->validate([
            'column' => 'nullable|in:' . implode(',', self::SORTABLE),
            'direction' => 'nullable|in:asc,desc',
            'per_page' => 'nullable|integer|min:5|max:100',
            'city_id' => 'nullable|string',
            'sub_area_id' => 'nullable|string',
            'billing' => 'nullable|in:subscription,commission,none',
            'plan_id' => 'nullable|string',
            'plan_state' => 'nullable|in:active,expiring,none',
            'gender_focus' => 'nullable|string|max:20',
        ]);

        $query = Salon::query()
            ->select('salons.*')
            ->with([
                'admin:id,name,phone,email',
                'city:id,name',
                'subArea:id,name',
                'currentSubscription.plan:id,name',
                'assignedCollaborator:id,name,email',
            ]);

        // Each figure is one correlated subquery, so the page stays a single
        // query and can be sorted on any of them.
        foreach ($this->figures() as $alias => $subquery) {
            $query->selectSub($subquery(), $alias);
        }

        if ($request->filled('search')) {
            $search = $request->input('search');
            $query->where(function ($q) use ($search) {
                $q->where('name', 'like', "%{$search}%")
                  ->orWhere('address', 'like', "%{$search}%")
                  ->orWhereHas('city', fn ($qc) => $qc->where('name', 'like', "%{$search}%"))
                  ->orWhereHas('subArea', fn ($qa) => $qa->where('name', 'like', "%{$search}%"))
                  ->orWhereHas('admin', fn ($qa) => $qa->where('name', 'like', "%{$search}%")->orWhere('phone', 'like', "%{$search}%"));
            });
        }

        $this->applyFilters($query, $request);

        $column = $request->input('column');
        $direction = $request->input('direction') === 'asc' ? 'asc' : 'desc';

        $sorts = $this->sorts();

        if ($column && in_array($column, ['name', 'status', 'created_at'], true)) {
            $query->orderBy("salons.{$column}", $direction);
        } elseif ($column && isset($sorts[$column])) {
            $query->orderBy($sorts[$column](), $direction);
        } else {
            // Legacy presets, kept so older clients keep working.
            match ($request->input('sort', 'created_at_desc')) {
                'name_asc' => $query->orderBy('salons.name', 'asc'),
                'name_desc' => $query->orderBy('salons.name', 'desc'),
                'created_at_asc' => $query->orderBy('salons.created_at', 'asc'),
                default => $query->orderBy('salons.created_at', 'desc'),
            };
        }

        // Name is the tie-breaker so paging never repeats or skips a row when
        // several salons share a sort value.
        $query->orderBy('salons.name', 'asc');

        $perPage = (int) $request->input('per_page', 20);
        $salons = $query->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => collect($salons->items())->map(fn (Salon $salon) => $salon->toArray() + [
                'current_plan' => $this->currentPlan($salon),
                'stats' => $this->rowStats($salon),
            ])->all(),
            'meta' => [
                'current_page' => $salons->currentPage(),
                'last_page' => $salons->lastPage(),
                'per_page' => $salons->perPage(),
                'total' => $salons->total(),
            ],
            'summary' => $this->summary(),
            'filters' => $this->filterOptions(),
        ]);
    }

    public function show($id)
    {
        $salon = Salon::with([
            'admin',
            'city',
            'subArea:id,name',
            'services.template.category',
            'providers.user',
            'combos.services',
            'currentSubscription.plan:id,name',
            'assignedCollaborator:id,name,email',
        ])->findOrFail($id);

        return response()->json([
            'success' => true,
            'data' => $salon->toArray() + [
                'current_plan' => $this->currentPlan($salon),
                'insights' => $this->insights($salon),
            ],
        ]);
    }

    /**
     * Put a collaborator on a salon — or take one off.
     *
     * A salon that came in through an enquiry already carries the collaborator
     * the enquiry was assigned to. A salon that registered itself from the
     * partner app and was approved straight away never passed through that
     * step, so without this there was no way to give it a collaborator at all.
     * The directory is the one place that holds every salon regardless of how
     * it arrived, which is why the assignment lives here.
     */
    public function assignCollaborator(Request $request, $id)
    {
        $request->validate([
            // Null clears the assignment, so a wrong pick can be undone.
            'collaborator_id' => 'nullable|exists:users,id',
        ]);

        $salon = Salon::findOrFail($id);

        $collaborator = $request->filled('collaborator_id')
            ? User::where('role', 'collaborator')->findOrFail($request->collaborator_id)
            : null;

        $previous = $salon->assignedCollaborator?->name;
        $salon->update(['assigned_collaborator_id' => $collaborator?->id]);

        AuditLogger::record(
            action: AuditLog::SALON_COLLABORATOR_ASSIGNED,
            entity: $salon,
            label: $salon->name,
            before: ['collaborator' => $previous],
            after: ['collaborator' => $collaborator?->name],
        );

        return response()->json([
            'success' => true,
            'message' => $collaborator
                ? "{$collaborator->name} is now the collaborator for {$salon->name}."
                : 'Collaborator removed from this salon.',
            'data' => $salon->fresh()->load('assignedCollaborator:id,name,email'),
        ]);
    }

    // ------------------------------------------------------------ figures

    /**
     * The per-salon figures the directory shows and sorts on, as correlated
     * subqueries. Every one returns a number (never null) so "highest first"
     * does not put salons with nothing at the top on PostgreSQL.
     *
     * @return array<string, \Closure(): \Illuminate\Database\Eloquent\Builder|\Illuminate\Database\Query\Builder>
     */
    private function figures(): array
    {
        $bookings = fn () => Appointment::query()->whereColumn('appointments.salon_id', 'salons.id');

        return [
            'bookings_count' => fn () => $bookings()->whereNotIn('status', self::NOT_A_BOOKING)->selectRaw('count(*)'),
            'completed_count' => fn () => $bookings()->where('status', 'completed')->selectRaw('count(*)'),
            'revenue_total' => fn () => $bookings()->where('status', 'completed')->selectRaw('coalesce(sum(total_amount), 0)'),
            'last_booking_at' => fn () => $bookings()->whereNotIn('status', self::NOT_A_BOOKING)->selectRaw('max(created_at)'),
            'rating_avg' => fn () => Review::query()->whereColumn('reviews.salon_id', 'salons.id')->selectRaw('coalesce(avg(rating), 0)'),
            'reviews_count' => fn () => Review::query()->whereColumn('reviews.salon_id', 'salons.id')->selectRaw('count(*)'),
            'staff_count' => fn () => ServiceProvider::query()->whereColumn('service_providers.salon_id', 'salons.id')
                ->where('is_active', true)->selectRaw('count(*)'),
            'services_count' => fn () => Service::query()->whereColumn('services.salon_id', 'salons.id')->selectRaw('count(*)'),
        ];
    }

    /** @return array<string, \Closure> */
    private function sorts(): array
    {
        $figures = $this->figures();

        return [
            'city' => fn () => City::query()->select('name')->whereColumn('cities.id', 'salons.city_id')->limit(1),
            'admin' => fn () => User::query()->select('name')->whereColumn('users.id', 'salons.admin_id')->limit(1),
            'collaborator' => fn () => User::query()->select('name')->whereColumn('users.id', 'salons.assigned_collaborator_id')->limit(1),
            // The active plan's name; salons with none sort together.
            'plan' => fn () => SubscriptionPlan::query()->select('subscription_plans.name')
                ->join('salon_subscriptions', 'salon_subscriptions.plan_id', '=', 'subscription_plans.id')
                ->whereColumn('salon_subscriptions.salon_id', 'salons.id')
                ->where('salon_subscriptions.status', 'active')
                ->orderByDesc('salon_subscriptions.start_date')
                ->limit(1),
            'bookings' => $figures['bookings_count'],
            'completed' => $figures['completed_count'],
            'revenue' => $figures['revenue_total'],
            'rating' => $figures['rating_avg'],
            'staff' => $figures['staff_count'],
            'services' => $figures['services_count'],
            // Never booked sorts as the oldest.
            'last_booking' => fn () => Appointment::query()->whereColumn('appointments.salon_id', 'salons.id')
                ->whereNotIn('status', self::NOT_A_BOOKING)
                ->selectRaw("coalesce(max(created_at), '1970-01-01 00:00:00')"),
        ];
    }

    private function applyFilters(Builder $query, Request $request): void
    {
        if ($request->filled('status')) {
            $query->where('salons.status', $request->input('status'));
        }

        if ($request->filled('collaborator_id')) {
            $request->collaborator_id === 'unassigned'
                ? $query->whereNull('assigned_collaborator_id')
                : $query->where('assigned_collaborator_id', $request->input('collaborator_id'));
        }

        if ($request->filled('city_id')) {
            $query->where('salons.city_id', $request->input('city_id'));
        }

        if ($request->filled('sub_area_id')) {
            $query->where('salons.sub_area_id', $request->input('sub_area_id'));
        }

        if ($request->filled('gender_focus')) {
            $query->where('salons.gender_focus', $request->input('gender_focus'));
        }

        // The plan a salon is on now: an active subscription row.
        $live = fn () => SalonSubscription::query()
            ->whereColumn('salon_subscriptions.salon_id', 'salons.id')
            ->where('salon_subscriptions.status', 'active');

        match ($request->input('billing')) {
            'subscription', 'commission' => $query->whereExists(
                $live()->where('billing_type', $request->input('billing'))
            ),
            'none' => $query->whereNotExists($live()),
            default => null,
        };

        if ($request->filled('plan_id')) {
            $request->plan_id === 'none'
                ? $query->whereNotExists($live())
                : $query->whereExists($live()->where('plan_id', $request->input('plan_id')));
        }

        $today = Carbon::today()->toDateString();
        $soon = Carbon::today()->addDays(self::EXPIRING_DAYS)->toDateString();

        match ($request->input('plan_state')) {
            'active' => $query->whereExists($live()->whereDate('end_date', '>=', $today)),
            'expiring' => $query->whereExists(
                $live()->whereDate('end_date', '>=', $today)->whereDate('end_date', '<=', $soon)
            ),
            // No live plan, or one past its end the hourly sweep has not caught.
            'none' => $query->whereNotExists($live()->whereDate('end_date', '>=', $today)),
            default => null,
        };
    }

    /** The row's figures, as the table and its CSV show them. */
    private function rowStats(Salon $salon): array
    {
        $completed = (int) $salon->completed_count;
        $revenue = round((float) $salon->revenue_total, 2);

        return [
            'bookings' => (int) $salon->bookings_count,
            'completed' => $completed,
            'revenue' => $revenue,
            'avg_ticket' => $completed > 0 ? round($revenue / $completed, 2) : 0,
            'rating' => $salon->reviews_count > 0 ? round((float) $salon->rating_avg, 1) : null,
            'reviews' => (int) $salon->reviews_count,
            'staff' => (int) $salon->staff_count,
            'services' => (int) $salon->services_count,
            'last_booking_at' => $salon->last_booking_at
                ? Carbon::parse($salon->last_booking_at)->toIso8601String()
                : null,
        ];
    }

    /** Head-counts across the whole platform, for the cards over the table. */
    private function summary(): array
    {
        $byStatus = Salon::query()->selectRaw('status, count(*) as total')->groupBy('status')->pluck('total', 'status');

        $today = Carbon::today()->toDateString();
        $withLivePlan = SalonSubscription::query()
            ->where('status', 'active')
            ->whereDate('end_date', '>=', $today)
            ->distinct()
            ->count('salon_id');

        return [
            'total' => (int) $byStatus->sum(),
            'active' => (int) ($byStatus['active'] ?? 0),
            'pending' => (int) ($byStatus['pending_approval'] ?? 0) + (int) ($byStatus['needs_correction'] ?? 0),
            'suspended' => (int) ($byStatus['suspended'] ?? 0),
            'with_live_plan' => $withLivePlan,
            'unassigned' => Salon::whereNull('assigned_collaborator_id')->count(),
            'revenue' => round((float) Appointment::where('status', 'completed')->sum('total_amount'), 2),
            'bookings' => Appointment::whereNotIn('status', self::NOT_A_BOOKING)->count(),
        ];
    }

    /** Only the cities, areas and plans that salons actually use. */
    private function filterOptions(): array
    {
        return [
            'cities' => City::query()
                ->whereIn('id', Salon::query()->select('city_id')->whereNotNull('city_id'))
                ->orderBy('name')->get(['id', 'name']),
            'sub_areas' => SubArea::query()
                ->whereIn('id', Salon::query()->select('sub_area_id')->whereNotNull('sub_area_id'))
                ->orderBy('name')->get(['id', 'name', 'city_id']),
            'plans' => SubscriptionPlan::withTrashed()
                ->whereIn('id', SalonSubscription::query()->select('plan_id')->where('status', 'active'))
                ->orWhere(fn ($q) => $q->whereNull('deleted_at')->where('is_active', true))
                ->orderBy('name')->get(['id', 'name']),
            'gender_focus' => Salon::query()->whereNotNull('gender_focus')->distinct()->orderBy('gender_focus')->pluck('gender_focus'),
        ];
    }

    /**
     * How one salon is doing, for its profile: bookings by outcome, money,
     * ratings, and its busiest services.
     */
    private function insights(Salon $salon): array
    {
        $base = fn () => Appointment::query()->where('salon_id', $salon->id);

        $byStatus = $base()->selectRaw('status, count(*) as total')->groupBy('status')->pluck('total', 'status');
        $completed = (int) ($byStatus['completed'] ?? 0);
        $revenue = round((float) $base()->where('status', 'completed')->sum('total_amount'), 2);
        $monthStart = Carbon::now()->startOfMonth();

        $reviews = Review::where('salon_id', $salon->id);
        $reviewCount = (clone $reviews)->count();

        $topServices = \Illuminate\Support\Facades\DB::table('appointment_services')
            ->join('appointments', 'appointments.id', '=', 'appointment_services.appointment_id')
            ->join('services', 'services.id', '=', 'appointment_services.service_id')
            ->leftJoin('service_templates', 'service_templates.id', '=', 'services.template_id')
            ->where('appointments.salon_id', $salon->id)
            ->where('appointments.status', 'completed')
            ->groupBy('appointment_services.service_id', 'service_templates.name')
            ->selectRaw('service_templates.name as name, count(*) as times')
            ->orderByDesc('times')
            ->limit(5)
            ->get()
            ->map(fn ($row) => ['name' => $row->name ?? 'Service', 'times' => (int) $row->times])
            ->all();

        return [
            'bookings' => [
                'total' => (int) $byStatus->except(self::NOT_A_BOOKING)->sum(),
                'completed' => $completed,
                'upcoming' => $base()->where('status', 'scheduled')
                    ->whereDate('appointment_date', '>=', Carbon::today()->toDateString())->count(),
                'cancelled' => (int) ($byStatus['cancelled'] ?? 0),
                'no_show' => (int) ($byStatus['no_show'] ?? 0),
                'this_month' => $base()->whereNotIn('status', self::NOT_A_BOOKING)
                    ->where('created_at', '>=', $monthStart)->count(),
                'walk_ins' => $base()->whereNotIn('status', self::NOT_A_BOOKING)
                    ->where('booking_source', 'walk_in')->count(),
                'last_at' => optional($base()->whereNotIn('status', self::NOT_A_BOOKING)->max('created_at'), fn ($v) => Carbon::parse($v)->toIso8601String()),
            ],
            'revenue' => [
                'total' => $revenue,
                'this_month' => round((float) $base()->where('status', 'completed')
                    ->where('updated_at', '>=', $monthStart)->sum('total_amount'), 2),
                'avg_ticket' => $completed > 0 ? round($revenue / $completed, 2) : 0,
            ],
            'rating' => [
                'average' => $reviewCount > 0 ? round((float) (clone $reviews)->avg('rating'), 1) : null,
                'count' => $reviewCount,
            ],
            'customers' => $base()->whereNotIn('status', self::NOT_A_BOOKING)
                ->whereNotNull('customer_id')->distinct()->count('customer_id'),
            'staff' => [
                'active' => $salon->providers->where('is_active', true)->count(),
                'total' => $salon->providers->count(),
            ],
            'services' => $salon->services->count(),
            'combos' => $salon->combos->count(),
            'top_services' => $topServices,
        ];
    }

    /**
     * The plan the salon is on right now, for the directory: its name, how it
     * pays, and when it runs out. Null when it has no active plan. A row still
     * marked active but past its end date (the hourly sweep has not caught it
     * yet) is reported as lapsed rather than as live.
     */
    private function currentPlan(Salon $salon): ?array
    {
        $subscription = $salon->currentSubscription;

        if (! $subscription) {
            return null;
        }

        $endDate = $subscription->end_date ? Carbon::parse($subscription->end_date)->startOfDay() : null;

        return [
            'name' => $subscription->plan?->name ?? 'Plan',
            'billing_type' => $subscription->billing_type,
            'billing_label' => \App\Support\BillingModel::label($subscription->billing_type),
            'end_date' => $endDate?->toDateString(),
            'days_left' => $endDate ? (int) now()->startOfDay()->diffInDays($endDate, false) : null,
            'lapsed' => $endDate !== null && $endDate->lt(now()->startOfDay()),
        ];
    }
}
