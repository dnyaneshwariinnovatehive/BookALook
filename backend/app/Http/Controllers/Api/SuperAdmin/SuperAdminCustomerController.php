<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Platform-wide customer intelligence for the owner.
 *
 * Read-only aggregation over users (role = customer), appointments and the
 * location tables. Everything the "Customers" page needs in one response:
 * headline KPIs, a signup trend, city distribution, a value leaderboard and a
 * searchable directory of every customer with their booking history.
 */
class SuperAdminCustomerController extends Controller
{
    /**
     * The master view. One response so the page renders from a single
     * round-trip: KPIs, growth curve, city split, top customers and the
     * paginated directory.
     */
    public function index(Request $request)
    {
        $now = Carbon::now();

        $page = max((int) $request->input('page', 1), 1);
        $perPage = (int) $request->input('per_page', 20);
        $search = trim((string) $request->input('search'));

        // Every customer, with their location and booking aggregates resolved
        // for the directory. The aggregates come from a single grouped subquery
        // so sorting on them stays SQL-side and pagination stays honest.
        $base = DB::table('users as u')
            ->leftJoin('cities as c', 'c.id', '=', 'u.city_id')
            ->leftJoin('sub_areas as sa', 'sa.id', '=', 'u.sub_area_id')
            ->leftJoin(
                DB::raw(
                    '(select customer_id,
                        count(*) as total,
                        count(case when status = "completed" then 1 else null end) as completed,
                        count(case when status = "cancelled" then 1 else null end) as cancelled,
                        count(case when status = "no_show" then 1 else null end) as no_show,
                        round(sum(case when status = "completed" then final_billed_amount else 0 end), 2) as spend
                      from appointments
                      where customer_id is not null and customer_id <> ""
                      group by customer_id) agg'
                ),
                'agg.customer_id', '=', 'u.id'
            )
            ->where('u.role', 'customer')
            ->selectRaw(
                'u.id, u.name, u.phone, u.email, u.gender, u.date_of_birth,
                 u.address, u.pincode, u.is_active, u.last_login_at, u.created_at,
                 c.name as city, sa.name as sub_area,
                 coalesce(agg.total, 0) as total_bookings,
                 coalesce(agg.completed, 0) as completed,
                 coalesce(agg.cancelled, 0) as cancelled,
                 coalesce(agg.no_show, 0) as no_show,
                 coalesce(agg.spend, 0) as spend'
            );

        $bookedIds = DB::table('appointments')
            ->whereNotNull('customer_id')
            ->distinct()
            ->pluck('customer_id');

        $repeatIds = DB::table('appointments')
            ->whereNotNull('customer_id')
            ->groupBy('customer_id')
            ->havingRaw('count(*) > 1')
            ->pluck('customer_id');

        $summary = [
            'total'          => (int) DB::table('users')->where('role', 'customer')->count(),
            'active'         => (int) DB::table('users')->where('role', 'customer')->where('is_active', true)->count(),
            'new_today'      => (int) DB::table('users')->where('role', 'customer')->whereDate('created_at', $now->toDateString())->count(),
            'new_this_month' => (int) DB::table('users')->where('role', 'customer')->whereMonth('created_at', $now->month)->whereYear('created_at', $now->year)->count(),
            'booked'         => $bookedIds->count(),
            'retained'       => $repeatIds->count(),
            'avg_spend'      => 0.0,
            'avg_bookings'   => 0.0,
        ];

        // Average value of a customer who has actually sounded a booking.
        if ($bookedIds->isNotEmpty()) {
            $value = DB::table('appointments')
                ->whereIn('customer_id', $bookedIds)
                ->where('status', 'completed')
                ->selectRaw('count(*) as bookings, sum(final_billed_amount) as spend')
                ->first();

            $totalBookings = DB::table('appointments')
                ->where('customer_id', '!=', '')
                ->whereNotNull('customer_id')
                ->count();

            $summary['avg_spend'] = round((float) ($value->spend ?? 0) / $bookedIds->count(), 2);
            $summary['avg_bookings'] = round($totalBookings / max($bookedIds->count(), 1), 1);
        }

        // Signups bucketed to the granularity the caller asked for.
        $summary['growth'] = $this->growthTrend(
            $request->input('granularity', 'day'),
            $now
        );

        // Where customers live, rolled up to the city level.
        $summary['cities'] = DB::table('users as u')
            ->leftJoin('cities as c', 'c.id', '=', 'u.city_id')
            ->where('u.role', 'customer')
            ->groupBy('c.name')
            ->selectRaw('coalesce(c.name, "Unassigned") as city, count(*) as customers,
                         sum(case when u.is_active then 1 else 0 end) as active')
            ->orderByDesc('customers')
            ->get()
            ->map(fn ($r) => [
                'city'      => $r->city,
                'customers' => (int) $r->customers,
                'active'    => (int) $r->active,
            ])
            ->all();

        // Most valuable customers by completed spend.
        $summary['top_customers'] = DB::table('appointments as a')
            ->join('users as u', 'u.id', '=', 'a.customer_id')
            ->where('a.status', 'completed')
            ->groupBy('u.id', 'u.name', 'u.phone')
            ->selectRaw(
                'u.id, u.name, u.phone, count(*) as bookings,
                 round(sum(a.final_billed_amount), 2) as spend'
            )
            ->orderByDesc('spend')
            ->limit(8)
            ->get()
            ->map(fn ($r) => [
                'id'       => $r->id,
                'name'     => $r->name,
                'phone'    => $r->phone,
                'bookings' => (int) $r->bookings,
                'spend'    => (float) $r->spend,
            ])
            ->all();

        // Customers who keep no-showing, worst first. The bookings total lets
        // the page show a no-show rate, which separates a one-off from a
        // pattern.
        $summary['top_no_shows'] = DB::table('appointments as a')
            ->join('users as u', 'u.id', '=', 'a.customer_id')
            ->leftJoin(
                DB::raw(
                    '(select customer_id, count(*) as total
                      from appointments
                      where customer_id is not null and customer_id <> ""
                      group by customer_id) t'
                ),
                't.customer_id', '=', 'u.id'
            )
            ->where('a.status', 'no_show')
            ->groupBy('u.id', 'u.name', 'u.phone', 't.total')
            ->selectRaw(
                'u.id, u.name, u.phone, count(*) as no_shows,
                 coalesce(t.total, 0) as bookings'
            )
            ->orderByDesc('no_shows')
            ->limit(8)
            ->get()
            ->map(fn ($r) => [
                'id'       => $r->id,
                'name'     => $r->name,
                'phone'    => $r->phone,
                'no_shows' => (int) $r->no_shows,
                'bookings' => (int) $r->bookings,
            ])
            ->all();

        // The directory: searchable, sortable, paginated. Sorts are resolved
        // against a whitelist so the column names can never be user text.
        $sortWhitelist = [
            'name'      => 'u.name',
            'city'      => 'c.name',
            'joined_at' => 'u.created_at',
            'last_seen' => 'u.last_login_at',
            'bookings'  => 'total_bookings',
            'completed' => 'completed',
            'cancelled' => 'cancelled',
            'no_show'   => 'no_show',
            'spend'     => 'spend',
            'status'    => 'u.is_active',
        ];

        $sortBy = (string) $request->input('sort_by', 'joined_at');
        if (! isset($sortWhitelist[$sortBy])) {
            $sortBy = 'joined_at';
        }
        $sortDir = strtolower((string) $request->input('sort_dir', 'desc')) === 'asc'
            ? 'asc'
            : 'desc';

        $query = clone $base;
        if ($search !== '') {
            $query->where(function ($q) use ($search) {
                $q->where('u.name', 'like', "%$search%")
                  ->orWhere('u.phone', 'like', "%$search%")
                  ->orWhere('u.email', 'like', "%$search%");
            });
        }

        $rows = $query->orderBy($sortWhitelist[$sortBy], $sortDir)
            ->orderByDesc('u.created_at')
            ->paginate($perPage, ['*'], 'page', $page)
            ->withQueryString();

        $customers = $rows->getCollection()->map(fn ($u) => [
            'id'          => $u->id,
            'name'        => $u->name,
            'phone'       => $u->phone,
            'email'       => $u->email,
            'gender'      => $u->gender,
            'address'     => $u->address,
            'pincode'     => $u->pincode,
            'city'        => $u->city,
            'sub_area'    => $u->sub_area,
            'is_active'   => (bool) $u->is_active,
            'joined_at'   => $u->created_at,
            'last_seen'   => $u->last_login_at,
            'bookings'    => (int) $u->total_bookings,
            'completed'   => (int) $u->completed,
            'cancelled'   => (int) $u->cancelled,
            'no_show'     => (int) $u->no_show,
            'spend'       => (float) ($u->spend ?? 0),
        ])->values();

        return response()->json([
            'success'     => true,
            'generated_at' => $now->toIso8601String(),
            'summary'     => $summary,
            'directory'   => [
                'data'        => $customers->all(),
                'total'       => $rows->total(),
                'per_page'    => $rows->perPage(),
                'current_page' => $rows->currentPage(),
                'last_page'   => $rows->lastPage(),
            ],
        ]);
    }

    /**
     * One customer in full: profile, location, booking history and reviews.
     * Backs the drawer/panel opened from the directory.
     */
    public function show(Request $request, string $id)
    {
        $user = DB::table('users as u')
            ->leftJoin('cities as c', 'c.id', '=', 'u.city_id')
            ->leftJoin('sub_areas as sa', 'sa.id', '=', 'u.sub_area_id')
            ->where('u.role', 'customer')
            ->where('u.id', $id)
            ->selectRaw(
                'u.id, u.name, u.phone, u.email, u.gender, u.date_of_birth,
                 u.address, u.pincode, u.is_active, u.last_login_at, u.created_at,
                 c.name as city, sa.name as sub_area'
            )
            ->first();

        if (!$user) {
            return response()->json(['success' => false, 'message' => 'Customer not found'], 404);
        }

        $agg = DB::table('appointments as a')
            ->selectRaw(
                'count(*) as total,
                 count(case when a.status = "completed" then 1 else null end) as completed,
                 count(case when a.status = "cancelled" then 1 else null end) as cancelled,
                 count(case when a.status = "no_show" then 1 else null end) as no_show,
                 round(sum(case when a.status = "completed" then a.final_billed_amount else 0 end), 2) as spend'
            )
            ->where('a.customer_id', $id)
            ->first();

        $appointments = DB::table('appointments as a')
            ->leftJoin('salons as s', 's.id', '=', 'a.salon_id')
            ->where('a.customer_id', $id)
            ->orderByDesc('a.appointment_date')
            ->limit(20)
            ->selectRaw(
                'a.id, a.appointment_date, a.start_time, a.end_time, a.status,
                 a.booking_source, a.final_billed_amount, a.created_at, s.name as salon_name'
            )
            ->get()
            ->map(fn ($r) => [
                'id'           => $r->id,
                'date'         => $r->appointment_date,
                'start'        => $r->start_time,
                'status'       => $r->status,
                'source'       => $r->booking_source,
                'billed'       => (float) ($r->final_billed_amount ?? 0),
                'created_at'   => $r->created_at,
                'salon'        => $r->salon_name,
            ])
            ->all();

        $reviews = DB::table('reviews as r')
            ->leftJoin('salons as s', 's.id', '=', 'r.salon_id')
            ->where('r.customer_id', $id)
            ->orderByDesc('r.created_at')
            ->limit(10)
            ->selectRaw('r.id, r.rating, r.comment, r.created_at, s.name as salon_name')
            ->get()
            ->map(fn ($r) => [
                'id'         => $r->id,
                'rating'     => (int) $r->rating,
                'comment'    => $r->comment,
                'created_at' => $r->created_at,
                'salon'      => $r->salon_name,
            ])
            ->all();

        return response()->json([
            'success' => true,
            'customer' => [
                'id'         => $user->id,
                'name'       => $user->name,
                'phone'      => $user->phone,
                'email'      => $user->email,
                'gender'     => $user->gender,
                'dob'        => $user->date_of_birth,
                'address'    => $user->address,
                'pincode'    => $user->pincode,
                'city'       => $user->city,
                'sub_area'   => $user->sub_area,
                'is_active'  => (bool) $user->is_active,
                'joined_at'  => $user->created_at,
                'last_seen'  => $user->last_login_at,
                'bookings'   => (int) $agg->total,
                'completed'  => (int) $agg->completed,
                'cancelled'  => (int) $agg->cancelled,
                'no_show'    => (int) $agg->no_show,
                'spend'      => (float) ($agg->spend ?? 0),
            ],
            'appointments' => $appointments,
            'reviews'      => $reviews,
        ]);
    }

    /**
     * New customer registrations over time, bucketed by day / week / month so
     * the growth curve always reads well whatever the volume of data.
     */
    private function growthTrend(string $granularity, Carbon $now): array
    {
        if (!in_array($granularity, ['day', 'week', 'month'], true)) {
            $granularity = 'day';
        }

        $days = DB::table('users')
            ->where('role', 'customer')
            ->where('created_at', '>=', $now->copy()->subDays(365)->startOfDay())
            ->selectRaw('date(created_at) as d, count(*) as c')
            ->groupBy('d')
            ->orderBy('d')
            ->get();

        $byKey = [];
        foreach ($days as $row) {
            $d = Carbon::parse($row->d);
            $key = match ($granularity) {
                'week'  => $d->startOfWeek()->toDateString(),
                'month' => $d->format('Y-m-01'),
                default => $d->toDateString(),
            };
            $byKey[$key] = ($byKey[$key] ?? 0) + (int) $row->c;
        }

        $trend = [];
        if ($granularity === 'month') {
            $cursor = $now->copy()->subMonths(11)->startOfMonth();
            while ($cursor->lte($now)) {
                $key = $cursor->format('Y-m-01');
                $trend[] = ['date' => $key, 'label' => $cursor->format('M Y'), 'customers' => $byKey[$key] ?? 0];
                $cursor->addMonth();
            }
        } elseif ($granularity === 'week') {
            $cursor = $now->copy()->subWeeks(19)->startOfWeek();
            while ($cursor->lte($now)) {
                $key = $cursor->toDateString();
                $trend[] = [
                    'date' => $key,
                    'label' => $cursor->format('d M') . ' – ' . $cursor->copy()->addDays(6)->format('d M'),
                    'customers' => $byKey[$key] ?? 0,
                ];
                $cursor->addWeek();
            }
        } else {
            $cursor = $now->copy()->subDays(29)->startOfDay();
            while ($cursor->lte($now)) {
                $key = $cursor->toDateString();
                $trend[] = [
                    'date' => $key,
                    'label' => $cursor->format('d M'),
                    'customers' => $byKey[$key] ?? 0,
                ];
                $cursor->addDay();
            }
        }

        return $trend;
    }
}