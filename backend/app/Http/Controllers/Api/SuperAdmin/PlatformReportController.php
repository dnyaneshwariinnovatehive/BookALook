<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Platform-wide reporting for the owner.
 *
 * Everything here is read-only aggregation over the operational tables
 * (appointments, salons, reviews, appointment_services and payouts), so the
 * owner can see the whole network at once, drill into a salon, city or service,
 * and pull any table out to Excel — all without touching how the rest of the
 * app operates.
 */
class PlatformReportController extends Controller
{
    /**
     * Headline KPIs every owner wants on one row: how big the network is, how
     * busy it is, how well it is received, and where the money sits.
     */
    public function overview(Request $request)
    {
        $now = Carbon::now();

        $salons = DB::table('salons')->selectRaw(
            'count(*) as total,
             sum(case when status = "active" then 1 else 0 end) as active,
             sum(case when status = "pending_approval" then 1 else 0 end) as pending,
             sum(case when status = "suspended" then 1 else 0 end) as suspended'
        )->first();

        $bookings = $this->appointmentCounts($now->copy()->startOfDay(), $now->copy()->startOfWeek(), $now->copy()->startOfMonth());

        $rating = DB::table('reviews')
            ->selectRaw('count(*) as review_count, round(avg(rating), 2) as average')
            ->first();

        $ratingDist = DB::table('reviews')
            ->selectRaw('rating, count(*) as count')
            ->groupBy('rating')
            ->orderBy('rating')
            ->get()
            ->mapWithKeys(fn ($r) => [(string) $r->rating => (int) $r->count])
            ->all();

        $topSalons = $this->topSalons(5);

        $cityBreakdown = $this->cityBreakdown(null, null, 5);

        $topServices = $this->topServices(null, null, 5);

        return response()->json([
            'success' => true,
            'generated_at' => $now->toIso8601String(),
            'salons' => [
                'total' => (int) $salons->total,
                'active' => (int) $salons->active,
                'pending' => (int) $salons->pending,
                'suspended' => (int) $salons->suspended,
            ],
            'bookings' => $bookings,
            'rating' => [
                'average' => $rating->average !== null ? (float) $rating->average : 0.0,
                'review_count' => (int) $rating->review_count,
                'distribution' => $ratingDist,
                'enabled' => $rating->review_count > 0,
            ],
            'top_salons' => $topSalons,
            'cities' => $cityBreakdown,
            'top_services' => $topServices,
            'revenue' => $this->revenueSummary(),
        ]);
    }

    /**
     * Per-salon table: the network, one salon per row, with booking load,
     * cancellations, no-shows, ratings and revenue. Optionally scoped to a
     * date window so the owner can review a single month.
     */
    public function salons(Request $request)
    {
        $from = $this->from($request);
        $to = $this->to($request);

        $rows = $this->salonTable($from, $to);

        return response()->json([
            'success' => true,
            'from' => $from?->toDateString(),
            'to' => $to?->toDateString(),
            'salons' => $rows,
            'totals' => $this->salonTotals($rows),
        ]);
    }

    /**
     * Area view: how well the network performs in each city — how many salons
     * trade there and how much they book.
     */
    public function cities(Request $request)
    {
        $rows = $this->cityBreakdown($this->from($request), $this->to($request));

        return response()->json(['success' => true, 'cities' => $rows]);
    }

    /**
     * Which services sell, across the whole network. Grouped by the category
     * and the template the service is built from.
     */
    public function services(Request $request)
    {
        $rows = $this->topServices($this->from($request), $this->to($request));

        return response()->json(['success' => true, 'services' => $rows]);
    }

    // ------------------------------------------------------------- internals

    private function appointmentCounts(Carbon $today, Carbon $week, Carbon $month): array
    {
        $row = DB::table('appointments')
            ->selectRaw(
                'count(*) as total,
                 sum(case when created_at >= ? then 1 else 0 end) as today,
                 sum(case when created_at >= ? then 1 else 0 end) as this_week,
                 sum(case when created_at >= ? then 1 else 0 end) as this_month,
                 sum(case when status = "completed" then 1 else 0 end) as completed,
                 sum(case when status = "cancelled" then 1 else 0 end) as cancelled,
                 sum(case when status = "no_show" then 1 else 0 end) as no_show,
                 sum(case when booking_source = "online" then 1 else 0 end) as online,
                 sum(case when booking_source = "walk_in" then 1 else 0 end) as walk_in',
                [$today, $week, $month]
            )
            ->first();

        $total = max((int) $row->total, 1);

        return [
            'total' => (int) $row->total,
            'today' => (int) $row->today,
            'week' => (int) $row->this_week,
            'month' => (int) $row->this_month,
            'completed' => (int) $row->completed,
            'online' => (int) $row->online,
            'walk_in' => (int) $row->walk_in,
            'cancellation_rate' => round(((int) $row->cancelled / $total) * 100, 1),
            'no_show_rate' => round(((int) $row->no_show / $total) * 100, 1),
        ];
    }

    private function revenueSummary(): array
    {
        $row = DB::table('salon_payouts')
            ->selectRaw(
                'sum(appointment_revenue) as appointment_revenue,
                 sum(commission_deducted) as commission_deducted,
                 sum(refund_adjustment) as refund_adjustment,
                 sum(wallet_redeemed_amount) as wallet_redeemed_amount,
                 sum(net_amount) as net_amount'
            )
            ->first();

        $completedRevenue = DB::table('appointments')
            ->where('status', 'completed')
            ->sum('final_billed_amount');

        return [
            'billed_by_salons' => round((float) $completedRevenue, 2),
            'payout_appointment_revenue' => round((float) ($row->appointment_revenue ?? 0), 2),
            'commission_earned' => round((float) ($row->commission_deducted ?? 0), 2),
            'refunds' => round((float) ($row->refund_adjustment ?? 0), 2),
            'coins_redeemed' => round((float) ($row->wallet_redeemed_amount ?? 0), 2),
            'net_to_salons' => round((float) ($row->net_amount ?? 0), 2),
        ];
    }

    private function salonTable(?Carbon $from, ?Carbon $to): array
    {
        $rows = DB::table('salons')
            ->leftJoin('cities', 'cities.id', '=', 'salons.city_id')
            ->leftJoin('appointments', 'appointments.salon_id', '=', 'salons.id')
            ->where(function ($q) use ($from, $to) {
                if ($from) {
                    $q->where('appointments.appointment_date', '>=', $from->toDateString());
                } else {
                    $q->whereNotNull('appointments.id');
                }
                if ($to) {
                    $q->where('appointments.appointment_date', '<=', $to->toDateString());
                }
            })
            ->selectRaw(
                'salons.id, salons.name, salons.status, cities.name as city,
                 salons.avg_rating, salons.review_count,
                 count(appointments.id) as total,
                 sum(case when appointments.status = "completed" then 1 else 0 end) as completed,
                 sum(case when appointments.status = "cancelled" then 1 else 0 end) as cancelled,
                 sum(case when appointments.status = "no_show" then 1 else 0 end) as no_show,
                 sum(case when appointments.status = "completed" then appointments.final_billed_amount else 0 end) as revenue'
            )
            ->groupBy('salons.id', 'salons.name', 'salons.status', 'cities.name', 'salons.avg_rating', 'salons.review_count')
            ->orderByDesc('revenue')
            ->get();

        return $rows->map(function ($s) {
            $total = max((int) $s->total, 1);
            return [
                'id' => $s->id,
                'name' => $s->name,
                'city' => $s->city,
                'status' => $s->status,
                'bookings' => (int) $s->total,
                'completed' => (int) $s->completed,
                'cancelled' => (int) $s->cancelled,
                'no_show' => (int) $s->no_show,
                'cancellation_rate' => round(((int) $s->cancelled / $total) * 100, 1),
                'no_show_rate' => round(((int) $s->no_show / $total) * 100, 1),
                'revenue' => round((float) ($s->revenue ?? 0), 2),
                'avg_rating' => (float) $s->avg_rating,
                'review_count' => (int) $s->review_count,
            ];
        })->all();
    }

    private function salonTotals(array $rows): array
    {
        $totals = [
            'bookings' => 0,
            'completed' => 0,
            'cancelled' => 0,
            'no_show' => 0,
            'revenue' => 0.0,
        ];
        foreach ($rows as $r) {
            $totals['bookings'] += $r['bookings'];
            $totals['completed'] += $r['completed'];
            $totals['cancelled'] += $r['cancelled'];
            $totals['no_show'] += $r['no_show'];
            $totals['revenue'] += $r['revenue'];
        }
        $base = max($totals['bookings'], 1);
        $totals['cancellation_rate'] = round(($totals['cancelled'] / $base) * 100, 1);
        $totals['no_show_rate'] = round(($totals['no_show'] / $base) * 100, 1);
        $totals['revenue'] = round($totals['revenue'], 2);
        return $totals;
    }

    private function topSalons(int $limit): array
    {
        $rows = DB::table('appointments')
            ->join('salons', 'salons.id', '=', 'appointments.salon_id')
            ->where('appointments.status', 'completed')
            ->selectRaw(
                'salons.id, salons.name, cities.name as city, count(*) as bookings,
                 round(sum(appointments.final_billed_amount), 2) as revenue'
            )
            ->leftJoin('cities', 'cities.id', '=', 'salons.city_id')
            ->groupBy('salons.id', 'salons.name', 'cities.name')
            ->orderByDesc('revenue')
            ->limit($limit)
            ->get();

        return $rows->map(fn ($s) => [
            'id' => $s->id,
            'name' => $s->name,
            'city' => $s->city,
            'bookings' => (int) $s->bookings,
            'revenue' => (float) $s->revenue,
        ])->all();
    }

    private function cityBreakdown(?Carbon $from, ?Carbon $to, ?int $limit = null): array
    {
        $rows = DB::table('salons')
            ->leftJoin('cities', 'cities.id', '=', 'salons.city_id')
            ->leftJoin('appointments', 'appointments.salon_id', '=', 'salons.id')
            ->where(function ($q) use ($from, $to) {
                if ($from) {
                    $q->where('appointments.appointment_date', '>=', $from->toDateString());
                } else {
                    $q->whereNotNull('appointments.id');
                }
                if ($to) {
                    $q->where('appointments.appointment_date', '<=', $to->toDateString());
                }
            })
            ->selectRaw(
                'cities.name as city,
                 count(distinct salons.id) as salons,
                 count(appointments.id) as bookings,
                 sum(case when appointments.status = "completed" then 1 else 0 end) as completed,
                 round(sum(case when appointments.status = "completed" then appointments.final_billed_amount else 0 end), 2) as revenue'
            )
            ->groupBy('cities.name')
            ->orderByDesc('revenue')
            ->get();

        $result = $rows->map(fn ($c) => [
            'city' => $c->city ?? 'Unknown',
            'salons' => (int) $c->salons,
            'bookings' => (int) $c->bookings,
            'completed' => (int) $c->completed,
            'revenue' => (float) $c->revenue,
        ])->all();

        if ($limit !== null) {
            $result = array_slice($result, 0, $limit);
        }

        return $result;
    }

    private function topServices(?Carbon $from, ?Carbon $to, ?int $limit = null): array
    {
        $rows = DB::table('appointment_services')
            ->join('services', 'services.id', '=', 'appointment_services.service_id')
            ->join('service_templates', 'service_templates.id', '=', 'services.template_id')
            ->leftJoin('service_categories', 'service_categories.id', '=', 'service_templates.category_id')
            ->leftJoin('appointments', 'appointments.id', '=', 'appointment_services.appointment_id')
            ->where(function ($q) use ($from, $to) {
                if ($from) {
                    $q->where('appointments.appointment_date', '>=', $from->toDateString());
                } else {
                    $q->whereNotNull('appointments.id');
                }
                if ($to) {
                    $q->where('appointments.appointment_date', '<=', $to->toDateString());
                }
            })
            ->selectRaw(
                'service_templates.name as service,
                 service_categories.name as category,
                 count(*) as bookings,
                 round(sum(appointment_services.price_at_booking), 2) as revenue'
            )
            ->groupBy('service_templates.name', 'service_categories.name')
            ->orderByDesc('bookings')
            ->get();

        $result = $rows->map(fn ($s) => [
            'service' => $s->service,
            'category' => $s->category ?? 'Uncategorised',
            'bookings' => (int) $s->bookings,
            'revenue' => (float) $s->revenue,
        ])->all();

        if ($limit !== null) {
            $result = array_slice($result, 0, $limit);
        }

        return $result;
    }

    private function from(Request $request): ?Carbon
    {
        return $request->filled('from') ? Carbon::parse($request->from) : null;
    }

    private function to(Request $request): ?Carbon
    {
        return $request->filled('to') ? Carbon::parse($request->to) : null;
    }
}
