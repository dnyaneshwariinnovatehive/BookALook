<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\SalonPayoutItem;
use App\Services\PayoutService;
use App\Services\PlatformCashPosition;
use Carbon\Carbon;
use Illuminate\Database\Query\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * The SuperAdmin analytics dashboard (Platform Reporting).
 *
 * One endpoint, one section per call, so each tab of the page loads on its
 * own: overview, money, bookings, places, salons, catalog, customers and
 * engagement. Every section takes the same scope — a date range (compared
 * with the same length of time just before it), an optional city and an
 * optional area — and answers it with grouped SQL, never a query per row.
 *
 * Definitions used throughout:
 *  - A booking is any appointment except a checkout still being paid for
 *    (`pending_payment`) or one the system cancelled because the payment hold
 *    ran out; those are counted apart as abandoned checkouts.
 *  - GMV is what completed visits were billed (final bill, else the booked
 *    total), dated by the visit.
 *  - Online money is what went through the payment gateway, dated when paid;
 *    at-salon money is cash/UPI the salon recorded at the counter.
 *  - BookALook's earnings are commission (as calculated into payouts, dated by
 *    the visit) plus Subscription Plan payments approved in the range.
 *
 * Queries stay portable between PostgreSQL (production) and SQLite (local):
 * dates are grouped by `substr(cast(col as varchar), 1, 10)` and bucketed into
 * weeks or months in PHP, and nothing takes MIN/MAX of a UUID column.
 */
class PlatformAnalyticsController extends Controller
{
    public const SECTIONS = ['options', 'overview', 'money', 'bookings', 'places', 'salons', 'catalog', 'customers', 'engagement'];

    private const WEEKDAYS = [1 => 'Mon', 2 => 'Tue', 3 => 'Wed', 4 => 'Thu', 5 => 'Fri', 6 => 'Sat', 0 => 'Sun'];

    private Carbon $from;
    private Carbon $to;
    private Carbon $prevFrom;
    private Carbon $prevTo;
    private string $granularity = 'daily';
    private ?string $cityId = null;
    private ?string $subAreaId = null;

    public function show(Request $request, string $section)
    {
        $data = $request->validate([
            'from' => 'nullable|date',
            'to' => 'nullable|date',
            'granularity' => 'nullable|in:daily,weekly,monthly',
            'city_id' => 'nullable|uuid',
            'sub_area_id' => 'nullable|uuid',
        ]);

        $this->scope($data);

        $payload = match ($section) {
            'options' => $this->options(),
            'overview' => $this->overview(),
            'money' => $this->money(),
            'bookings' => $this->bookings(),
            'places' => $this->places(),
            'salons' => $this->salons(),
            'catalog' => $this->catalog(),
            'customers' => $this->customers(),
            'engagement' => $this->engagement(),
        };

        return response()->json([
            'success' => true,
            'section' => $section,
            'generated_at' => Carbon::now()->toIso8601String(),
            'range' => [
                'from' => $this->from->toDateString(),
                'to' => $this->to->toDateString(),
                'previous_from' => $this->prevFrom->toDateString(),
                'previous_to' => $this->prevTo->toDateString(),
                'days' => $this->days(),
                'granularity' => $this->granularity,
            ],
            'filters' => [
                'city_id' => $this->cityId,
                'city' => $this->cityId ? DB::table('cities')->where('id', $this->cityId)->value('name') : null,
                'sub_area_id' => $this->subAreaId,
                'sub_area' => $this->subAreaId ? DB::table('sub_areas')->where('id', $this->subAreaId)->value('name') : null,
            ],
        ] + $payload);
    }

    // ================================================================= options

    /** The cities that have salons, each with its areas, for the filter bar. */
    private function options(): array
    {
        $counts = DB::table('salons')->whereNull('deleted_at')->whereNotNull('city_id')
            ->groupBy('city_id')->selectRaw('city_id, count(*) as n')->pluck('n', 'city_id');
        $cities = $counts->isEmpty() ? collect() : DB::table('cities')->whereIn('id', $counts->keys()->all())->orderBy('name')->get(['id', 'name']);
        $areas = $cities->isEmpty() ? collect() : DB::table('sub_areas')->whereIn('city_id', $cities->pluck('id')->all())->orderBy('name')->get(['id', 'city_id', 'name'])->groupBy('city_id');

        return [
            'cities' => $cities->map(fn ($c) => [
                'id' => (string) $c->id,
                'name' => $c->name,
                'salons' => (int) ($counts[$c->id] ?? 0),
                'areas' => ($areas[$c->id] ?? collect())->map(fn ($a) => ['id' => (string) $a->id, 'name' => $a->name])->values()->all(),
            ])->values()->all(),
        ];
    }

    // ================================================================ overview

    private function overview(): array
    {
        $current = $this->kpis($this->from, $this->to);
        $previous = $this->kpis($this->prevFrom, $this->prevTo);

        $trend = $this->series([
            'gmv' => $this->perDay($this->bookingsIn($this->from, $this->to), 'a.appointment_date', $this->gmvSql()),
            'bookings' => $this->perDay($this->bookingsIn($this->from, $this->to), 'a.appointment_date', 'count(*)'),
            'completed' => $this->perDay($this->bookingsIn($this->from, $this->to), 'a.appointment_date', "sum(case when a.status = 'completed' then 1 else 0 end)"),
            'online_collected' => $this->perDay($this->onlinePayments($this->from, $this->to), 'p.paid_at', 'sum(p.amount)'),
            'commission' => $this->perDay($this->commissionLines($this->from, $this->to), 'a.appointment_date', 'sum(spi.commission_amount)'),
            'plans' => $this->perDay($this->planPayments($this->from, $this->to), 'r.updated_at', 'sum(' . $this->planCashSql() . ')'),
        ]);
        foreach ($trend as &$point) {
            $point['earnings'] = round($point['commission'] + $point['plans'], 2);
        }
        unset($point);

        $best = collect($trend)->sortByDesc('gmv')->first();

        $topCity = $this->bookingsIn($this->from, $this->to)
            ->leftJoin('cities as c', 'c.id', '=', 's.city_id')
            ->groupBy('c.name')
            ->selectRaw('c.name as name, ' . $this->gmvSql() . ' as gmv')
            ->orderByDesc('gmv')
            ->first();

        $topSalon = $this->bookingsIn($this->from, $this->to)
            ->groupBy('s.id', 's.name')
            ->selectRaw('s.id, s.name, ' . $this->gmvSql() . ' as gmv')
            ->orderByDesc('gmv')
            ->first();

        $topService = $this->linesIn($this->from, $this->to)
            ->join('services as sv', 'sv.id', '=', 'l.service_id')
            ->join('service_templates as st', 'st.id', '=', 'sv.template_id')
            ->groupBy('st.name')
            ->selectRaw('st.name as name, count(*) as n')
            ->orderByDesc('n')
            ->first();

        return [
            'kpis' => ['current' => $current, 'previous' => $previous],
            'trend' => $trend,
            'status_mix' => [
                ['key' => 'completed', 'label' => 'Completed', 'value' => $current['completed']],
                ['key' => 'upcoming', 'label' => 'Upcoming / in chair', 'value' => $current['upcoming']],
                ['key' => 'cancelled', 'label' => 'Cancelled', 'value' => $current['cancelled']],
                ['key' => 'no_show', 'label' => 'No-show', 'value' => $current['no_show']],
            ],
            'source_mix' => [
                ['key' => 'app', 'label' => 'Booked in the app', 'value' => $current['bookings'] - $current['walk_in']],
                ['key' => 'walk_in', 'label' => 'Walk-in', 'value' => $current['walk_in']],
            ],
            'highlights' => [
                'best_bucket' => $best && $best['gmv'] > 0 ? ['label' => $best['label'], 'gmv' => $best['gmv']] : null,
                'top_city' => $topCity && (float) $topCity->gmv > 0 ? ['name' => $topCity->name ?? 'No city', 'gmv' => $this->r($topCity->gmv)] : null,
                'top_salon' => $topSalon && (float) $topSalon->gmv > 0 ? ['id' => (string) $topSalon->id, 'name' => $topSalon->name, 'gmv' => $this->r($topSalon->gmv)] : null,
                'top_service' => $topService ? ['name' => $topService->name, 'bookings' => (int) $topService->n] : null,
            ],
        ];
    }

    /** The headline numbers for one window. */
    private function kpis(Carbon $from, Carbon $to): array
    {
        $b = $this->bookingsIn($from, $to)
            ->selectRaw($this->statusSql() . ', count(distinct case when a.status = \'completed\' then a.customer_id end) as customers, count(distinct case when a.status = \'completed\' then a.salon_id end) as trading_salons')
            ->first();

        $abandoned = (int) $this->scoped(DB::table('appointments as a')->join('salons as s', 's.id', '=', 'a.salon_id'))
            ->whereBetween('a.appointment_date', [$from->toDateString(), $to->toDateString()])
            ->where(fn ($q) => $q->where('a.status', 'pending_payment')
                ->orWhere(fn ($c) => $c->where('a.status', 'cancelled')->where('a.cancelled_by', 'system')))
            ->count();

        $online = (float) $this->onlinePayments($from, $to)->sum('p.amount');
        $atSalon = (float) $this->scoped($this->paymentsBase($from, $to))->whereNull('p.gateway')->sum('p.amount');
        $refunds = (float) $this->refundsIn($from, $to)->sum('r.amount');
        $commission = (float) $this->commissionLines($from, $to)->sum('spi.commission_amount');
        $plans = (float) $this->planPayments($from, $to)->selectRaw('coalesce(sum(' . $this->planCashSql() . '), 0) as v')->value('v');
        $paidOut = (float) $this->scoped(DB::table('salon_payouts as sp')->join('salons as s', 's.id', '=', 'sp.salon_id'))
            ->where('sp.status', PayoutService::STATUS_DISTRIBUTED)
            ->where('sp.net_amount', '>', 0)
            ->whereBetween('sp.distributed_at', [$from->copy()->startOfDay(), $to->copy()->endOfDay()])
            ->sum('sp.net_amount');
        $reviews = $this->scoped(DB::table('reviews as rv')->join('salons as s', 's.id', '=', 'rv.salon_id'))
            ->whereBetween('rv.created_at', [$from->copy()->startOfDay(), $to->copy()->endOfDay()])
            ->selectRaw('count(*) as n, avg(rv.rating) as avg')
            ->first();
        $newCustomers = $this->newCustomers($from, $to);

        $bookings = (int) $b->bookings;
        $completed = (int) $b->completed;
        $gmv = $this->r($b->gmv);
        $customers = (int) $b->customers;

        return [
            'gmv' => $gmv,
            'bookings' => $bookings,
            'completed' => $completed,
            'cancelled' => (int) $b->cancelled,
            'no_show' => (int) $b->no_show,
            'upcoming' => (int) $b->upcoming,
            'walk_in' => (int) $b->walk_in,
            'abandoned_checkouts' => $abandoned,
            'completion_rate' => $this->pct($completed, $bookings - (int) $b->upcoming),
            'cancellation_rate' => $this->pct((int) $b->cancelled, $bookings),
            'no_show_rate' => $this->pct((int) $b->no_show, $bookings),
            'avg_ticket' => $completed > 0 ? $this->r($gmv / $completed) : 0,
            'customers' => $customers,
            'new_customers' => $newCustomers,
            'returning_customers' => max(0, $customers - $newCustomers),
            'trading_salons' => (int) $b->trading_salons,
            'online_collected' => $this->r($online),
            'at_salon_collected' => $this->r($atSalon),
            'online_share' => $this->pct($online, $online + $atSalon),
            'refunds' => $this->r($refunds),
            'commission' => $this->r($commission),
            'plan_payments' => $this->r($plans),
            'earnings' => $this->r($commission + $plans),
            'take_rate' => $this->pct($commission + $plans, $gmv),
            'paid_to_salons' => $this->r($paidOut),
            'reviews' => (int) $reviews->n,
            'avg_rating' => $reviews->avg !== null ? round((float) $reviews->avg, 2) : null,
        ];
    }

    // =================================================================== money

    private function money(): array
    {
        $flows = fn (Carbon $from, Carbon $to) => $this->flows($from, $to);

        $trend = $this->series([
            'online' => $this->perDay($this->onlinePayments($this->from, $this->to), 'p.paid_at', 'sum(p.amount)'),
            'at_salon' => $this->perDay($this->scoped($this->paymentsBase($this->from, $this->to))->whereNull('p.gateway'), 'p.paid_at', 'sum(p.amount)'),
            'refunds' => $this->perDay($this->refundsIn($this->from, $this->to), 'r.created_at', 'sum(r.amount)'),
            'paid_to_salons' => $this->perDay(
                $this->payoutsDistributed($this->from, $this->to)->where('sp.net_amount', '>', 0),
                'sp.distributed_at',
                'sum(sp.net_amount)'
            ),
            'commission' => $this->perDay($this->commissionLines($this->from, $this->to), 'a.appointment_date', 'sum(spi.commission_amount)'),
            'plans' => $this->perDay($this->planPayments($this->from, $this->to), 'r.updated_at', 'sum(' . $this->planCashSql() . ')'),
        ]);

        $types = $this->scoped($this->paymentsBase($this->from, $this->to))
            ->groupBy('p.payment_type', 'p.payment_mode')
            ->selectRaw("p.payment_type, p.payment_mode, case when p.gateway is null then 'at_salon' else 'online' end as channel, count(*) as n, coalesce(sum(p.amount), 0) as amount")
            ->groupByRaw('case when p.gateway is null then \'at_salon\' else \'online\' end')
            ->get()
            ->map(fn ($r) => [
                'channel' => $r->channel,
                'type' => $r->payment_type ?? 'other',
                'mode' => $r->payment_mode ?? 'unknown',
                'label' => $this->paymentLabel($r->channel, $r->payment_type, $r->payment_mode),
                'count' => (int) $r->n,
                'amount' => $this->r($r->amount),
            ])
            ->sortByDesc('amount')->values()->all();

        // How each booking was paid for: nothing online, its advance, or in full.
        $paid = DB::table('payments')
            ->where('status', 'success')->whereNotNull('gateway')
            ->groupBy('appointment_id')
            ->selectRaw('appointment_id, sum(amount) as paid');
        $mix = $this->bookingsIn($this->from, $this->to)
            ->leftJoinSub($paid, 'pp', 'pp.appointment_id', '=', 'a.id')
            ->selectRaw("case when coalesce(pp.paid, 0) <= 0 then 'at_salon' when pp.paid + 0.5 >= coalesce(a.total_amount, 0) then 'full' else 'advance' end as mix, count(*) as n, coalesce(sum(pp.paid), 0) as online, " . $this->gmvSql() . ' as gmv')
            ->groupBy('mix')
            ->get()
            ->keyBy('mix');
        $mixLabels = ['advance' => 'Advance paid online', 'full' => 'Paid in full online', 'at_salon' => 'Nothing paid online'];
        $paymentMix = collect($mixLabels)->map(fn ($label, $key) => [
            'key' => $key,
            'label' => $label,
            'bookings' => (int) ($mix[$key]->n ?? 0),
            'online' => $this->r($mix[$key]->online ?? 0),
            'gmv' => $this->r($mix[$key]->gmv ?? 0),
        ])->values()->all();

        $options = $this->bookingsIn($this->from, $this->to)
            ->groupBy('a.payment_option')
            ->selectRaw('a.payment_option as k, count(*) as n')
            ->pluck('n', 'k')
            ->map(fn ($n) => (int) $n)
            ->all();

        $refundBase = fn () => $this->scoped(
            DB::table('payment_refunds as r')
                ->join('payments as p', 'p.id', '=', 'r.payment_id')
                ->join('appointments as a', 'a.id', '=', 'r.appointment_id')
                ->join('salons as s', 's.id', '=', 'a.salon_id')
        )->whereNotNull('p.gateway')
            ->whereBetween('r.created_at', [$this->from->copy()->startOfDay(), $this->to->copy()->endOfDay()]);

        $refundStatus = $refundBase()->groupBy('r.status')
            ->selectRaw('r.status, count(*) as n, coalesce(sum(r.amount), 0) as amount')
            ->get()
            ->map(fn ($r) => ['status' => $r->status, 'count' => (int) $r->n, 'amount' => $this->r($r->amount)])
            ->sortByDesc('amount')->values()->all();
        $refundReasons = $refundBase()->where('r.status', '!=', 'failed')->groupBy('r.reason')
            ->selectRaw('r.reason, count(*) as n, coalesce(sum(r.amount), 0) as amount')
            ->orderByDesc('amount')->limit(8)->get()
            ->map(fn ($r) => ['reason' => $r->reason ?: 'No reason given', 'count' => (int) $r->n, 'amount' => $this->r($r->amount)])
            ->all();
        $refundSalons = $refundBase()->where('r.status', '!=', 'failed')->groupBy('s.id', 's.name')
            ->selectRaw('s.id, s.name, count(*) as n, coalesce(sum(r.amount), 0) as amount')
            ->orderByDesc('amount')->limit(8)->get()
            ->map(fn ($r) => ['id' => (string) $r->id, 'name' => $r->name, 'count' => (int) $r->n, 'amount' => $this->r($r->amount)])
            ->all();

        // Payouts whose cycle closed in the range, by where they stand.
        $payouts = $this->scoped(DB::table('salon_payouts as sp')->join('salons as s', 's.id', '=', 'sp.salon_id'))
            ->whereBetween('sp.cycle_end_date', [$this->from->toDateString(), $this->to->toDateString()])
            ->groupBy('sp.status', 'sp.billing_type')
            ->selectRaw('sp.status, sp.billing_type, count(*) as n, coalesce(sum(sp.gross_amount), 0) as gross, coalesce(sum(sp.commission_deducted), 0) as commission, coalesce(sum(sp.refund_adjustment), 0) as refunds, coalesce(sum(sp.wallet_redeemed_amount), 0) as coins, coalesce(sum(case when sp.net_amount > 0 then sp.net_amount else 0 end), 0) as to_salons, coalesce(sum(case when sp.net_amount < 0 then -sp.net_amount else 0 end), 0) as from_salons')
            ->get()
            ->map(fn ($r) => [
                'status' => $r->status,
                'billing' => $r->billing_type === 'commission' ? 'Commission Model' : 'Subscription Plan',
                'count' => (int) $r->n,
                'gross' => $this->r($r->gross),
                'commission' => $this->r($r->commission),
                'refunds' => $this->r($r->refunds),
                'coins' => $this->r($r->coins),
                'to_salons' => $this->r($r->to_salons),
                'from_salons' => $this->r($r->from_salons),
            ])->values()->all();

        $plans = $this->planPayments($this->from, $this->to)
            ->leftJoin('subscription_plans as pl', 'pl.id', '=', 'r.subscription_plan_id')
            ->groupBy('pl.name')
            ->selectRaw('pl.name as name, count(*) as n, coalesce(sum(' . $this->planCashSql() . '), 0) as amount, coalesce(sum(r.coin_discount_inr), 0) as coins')
            ->get()
            ->map(fn ($r) => ['name' => $r->name ?? 'Plan', 'count' => (int) $r->n, 'amount' => $this->r($r->amount), 'coins' => $this->r($r->coins)])
            ->sortByDesc('amount')->values()->all();

        return [
            'cash_position' => app(PlatformCashPosition::class)->snapshot(),
            'flows' => ['current' => $flows($this->from, $this->to), 'previous' => $flows($this->prevFrom, $this->prevTo)],
            'trend' => $trend,
            'payment_types' => $types,
            'payment_mix' => $paymentMix,
            'payment_options' => $options,
            'refunds' => ['by_status' => $refundStatus, 'by_reason' => $refundReasons, 'by_salon' => $refundSalons],
            'payouts' => $payouts,
            'plans' => $plans,
        ];
    }

    /** Money that moved in one window. */
    private function flows(Carbon $from, Carbon $to): array
    {
        $online = $this->onlinePayments($from, $to)
            ->selectRaw("coalesce(sum(p.amount), 0) as total, count(*) as n, coalesce(sum(case when p.payment_type = 'advance' then p.amount else 0 end), 0) as advance, coalesce(sum(case when p.gateway = 'razorpay' then p.amount else 0 end), 0) as razorpay")
            ->first();
        $atSalon = (float) $this->scoped($this->paymentsBase($from, $to))->whereNull('p.gateway')->sum('p.amount');
        $refunds = $this->refundsIn($from, $to)
            ->selectRaw("coalesce(sum(case when r.status = 'processed' then r.amount else 0 end), 0) as processed, coalesce(sum(case when r.status <> 'processed' then r.amount else 0 end), 0) as queued, count(*) as n")
            ->first();
        $payouts = $this->payoutsDistributed($from, $to)
            ->selectRaw('coalesce(sum(case when sp.net_amount > 0 then sp.net_amount else 0 end), 0) as paid, coalesce(sum(case when sp.net_amount < 0 then -sp.net_amount else 0 end), 0) as dues, coalesce(sum(sp.wallet_redeemed_amount), 0) as coins')
            ->first();
        $commission = (float) $this->commissionLines($from, $to)->sum('spi.commission_amount');
        $plans = (float) $this->planPayments($from, $to)->selectRaw('coalesce(sum(' . $this->planCashSql() . '), 0) as v')->value('v');
        $feePercent = (float) config('services.payments.razorpay.fee_percent', 2.36);
        $total = (float) $online->total;

        return [
            'online_collected' => $this->r($total),
            'online_payments' => (int) $online->n,
            'online_advance' => $this->r($online->advance),
            'online_other' => $this->r($total - (float) $online->advance),
            'at_salon_collected' => $this->r($atSalon),
            'gateway_fee_estimate' => $this->r((float) $online->razorpay * $feePercent / 100),
            'refunds_processed' => $this->r($refunds->processed),
            'refunds_queued' => $this->r($refunds->queued),
            'refund_count' => (int) $refunds->n,
            'refund_rate' => $this->pct((float) $refunds->processed + (float) $refunds->queued, $total),
            'paid_to_salons' => $this->r($payouts->paid),
            'dues_collected' => $this->r($payouts->dues),
            'coins_against_commission' => $this->r($payouts->coins),
            'commission' => $this->r($commission),
            'plan_payments' => $this->r($plans),
            'earnings' => $this->r($commission + $plans),
        ];
    }

    // ================================================================ bookings

    private function bookings(): array
    {
        $k = $this->kpis($this->from, $this->to);

        $trend = $this->series([
            'completed' => $this->perDay($this->bookingsIn($this->from, $this->to), 'a.appointment_date', "sum(case when a.status = 'completed' then 1 else 0 end)"),
            'cancelled' => $this->perDay($this->bookingsIn($this->from, $this->to), 'a.appointment_date', "sum(case when a.status = 'cancelled' then 1 else 0 end)"),
            'no_show' => $this->perDay($this->bookingsIn($this->from, $this->to), 'a.appointment_date', "sum(case when a.status = 'no_show' then 1 else 0 end)"),
            'upcoming' => $this->perDay($this->bookingsIn($this->from, $this->to), 'a.appointment_date', "sum(case when a.status in ('scheduled', 'in_progress') then 1 else 0 end)"),
        ]);

        $cancelledBy = $this->bookingsIn($this->from, $this->to)
            ->where('a.status', 'cancelled')
            ->groupBy('a.cancelled_by')
            ->selectRaw('a.cancelled_by as k, count(*) as n')
            ->get()
            ->groupBy(fn ($r) => match (true) {
                $r->k === 'customer' => 'Customer',
                in_array($r->k, ['salon', 'admin', 'partner', 'staff'], true) => 'Salon',
                $r->k === null || $r->k === '' => 'Not recorded',
                default => 'Salon or BookALook staff',
            })
            ->map(fn ($g, $label) => ['label' => $label, 'count' => (int) $g->sum('n')])
            ->sortByDesc('count')->values()->all();

        $reasons = $this->bookingsIn($this->from, $this->to)
            ->where('a.status', 'cancelled')
            ->groupBy('a.cancellation_reason')
            ->selectRaw('a.cancellation_reason as reason, count(*) as n')
            ->orderByDesc('n')->limit(8)->get()
            ->map(fn ($r) => ['reason' => $r->reason ?: 'No reason given', 'count' => (int) $r->n])
            ->all();

        // Lead time: how far ahead people book. Grouped by both dates, so the
        // row count is bounded by days × days, never by bookings.
        $lead = $this->bookingsIn($this->from, $this->to)
            ->whereNull('a.walk_in_customer_name')
            ->where('a.booking_source', '!=', 'walk_in')
            ->groupBy('a.appointment_date')
            ->groupByRaw($this->day('a.created_at'))
            ->selectRaw('a.appointment_date as d, ' . $this->day('a.created_at') . ' as c, count(*) as n')
            ->get();
        $leadBands = ['Same day' => 0, 'Next day' => 0, '2–3 days' => 0, '4–7 days' => 0, '8–14 days' => 0, '15+ days' => 0];
        foreach ($lead as $row) {
            $gap = (int) Carbon::parse(substr((string) $row->c, 0, 10))->diffInDays(Carbon::parse(substr((string) $row->d, 0, 10)), false);
            $band = match (true) {
                $gap <= 0 => 'Same day',
                $gap === 1 => 'Next day',
                $gap <= 3 => '2–3 days',
                $gap <= 7 => '4–7 days',
                $gap <= 14 => '8–14 days',
                default => '15+ days',
            };
            $leadBands[$band] += (int) $row->n;
        }

        // Heatmap: weekday × hour of the visit.
        $hourSql = 'substr(cast(a.start_time as varchar), 1, 2)';
        $cells = $this->bookingsIn($this->from, $this->to)
            ->groupBy('a.appointment_date')
            ->groupByRaw($hourSql)
            ->selectRaw("a.appointment_date as d, {$hourSql} as h, count(*) as n, sum(case when a.status = 'completed' then 1 else 0 end) as done, " . $this->gmvSql() . ' as gmv')
            ->get();
        $grid = [];
        $weekdays = [];
        $hours = [];
        foreach ($cells as $c) {
            $dow = Carbon::parse(substr((string) $c->d, 0, 10))->dayOfWeek;
            $h = (int) $c->h;
            $grid[$dow][$h] = ($grid[$dow][$h] ?? 0) + (int) $c->n;
            $weekdays[$dow]['bookings'] = ($weekdays[$dow]['bookings'] ?? 0) + (int) $c->n;
            $weekdays[$dow]['completed'] = ($weekdays[$dow]['completed'] ?? 0) + (int) $c->done;
            $weekdays[$dow]['gmv'] = ($weekdays[$dow]['gmv'] ?? 0) + (float) $c->gmv;
            $hours[$h] = ($hours[$h] ?? 0) + (int) $c->n;
        }
        $hourKeys = $hours ? range(min(array_keys($hours)), max(array_keys($hours))) : range(9, 21);
        $heatmap = [];
        foreach (self::WEEKDAYS as $dow => $label) {
            $heatmap[] = [
                'day' => $label,
                'cells' => array_map(fn ($h) => ['hour' => $h, 'count' => $grid[$dow][$h] ?? 0], $hourKeys),
            ];
        }
        $dayCounts = $this->weekdayCounts();
        $byWeekday = [];
        foreach (self::WEEKDAYS as $dow => $label) {
            $n = $weekdays[$dow]['bookings'] ?? 0;
            $byWeekday[] = [
                'day' => $label,
                'bookings' => $n,
                'completed' => $weekdays[$dow]['completed'] ?? 0,
                'gmv' => $this->r($weekdays[$dow]['gmv'] ?? 0),
                'per_day' => $dayCounts[$dow] > 0 ? round($n / $dayCounts[$dow], 1) : 0,
            ];
        }

        $other = $this->bookingsIn($this->from, $this->to)
            ->selectRaw("sum(case when a.rescheduled_from_id is not null then 1 else 0 end) as rescheduled, sum(case when a.booked_for is not null and a.booked_for <> 'self' then 1 else 0 end) as for_others, sum(case when a.first_time_offer_id is not null then 1 else 0 end) as with_offer, sum(case when a.status = 'completed' and a.payment_collected_at is not null then 1 else 0 end) as collected")
            ->first();

        return [
            'kpis' => $k,
            'previous' => $this->kpis($this->prevFrom, $this->prevTo),
            'trend' => $trend,
            'funnel' => [
                ['key' => 'started', 'label' => 'Checkouts started', 'value' => $k['bookings'] + $k['abandoned_checkouts'] - $k['walk_in']],
                ['key' => 'confirmed', 'label' => 'Bookings confirmed', 'value' => $k['bookings'] - $k['walk_in']],
                ['key' => 'reached', 'label' => 'Reached the visit date', 'value' => $k['bookings'] - $k['walk_in'] - $k['upcoming']],
                ['key' => 'completed', 'label' => 'Completed', 'value' => (int) $this->bookingsIn($this->from, $this->to)->where('a.status', 'completed')->whereNull('a.walk_in_customer_name')->where('a.booking_source', '!=', 'walk_in')->count()],
            ],
            'outcomes' => [
                ['key' => 'completed', 'label' => 'Completed', 'value' => $k['completed']],
                ['key' => 'upcoming', 'label' => 'Upcoming / in chair', 'value' => $k['upcoming']],
                ['key' => 'cancelled', 'label' => 'Cancelled', 'value' => $k['cancelled']],
                ['key' => 'no_show', 'label' => 'No-show', 'value' => $k['no_show']],
                ['key' => 'abandoned', 'label' => 'Checkout abandoned', 'value' => $k['abandoned_checkouts']],
            ],
            'cancelled_by' => $cancelledBy,
            'cancellation_reasons' => $reasons,
            'lead_time' => collect($leadBands)->map(fn ($n, $label) => ['label' => $label, 'count' => $n])->values()->all(),
            'heatmap' => ['hours' => $hourKeys, 'rows' => $heatmap, 'max' => $grid ? max(array_map('max', $grid)) : 0],
            'by_weekday' => $byWeekday,
            'by_hour' => array_map(fn ($h) => ['hour' => $h, 'label' => sprintf('%02d:00', $h), 'bookings' => $hours[$h] ?? 0], $hourKeys),
            'other' => [
                'rescheduled' => (int) $other->rescheduled,
                'booked_for_others' => (int) $other->for_others,
                'with_first_time_offer' => (int) $other->with_offer,
                'avg_per_day' => round($k['bookings'] / max(1, $this->days()), 1),
            ],
        ];
    }

    // ================================================================== places

    private function places(): array
    {
        $cur = fn (string $group) => $this->bookingsIn($this->from, $this->to)
            ->groupBy(...$this->groupCols($group))
            ->selectRaw($this->groupSelect($group) . ', ' . $this->statusSql() . ', count(distinct case when a.status = \'completed\' then a.customer_id end) as customers')
            ->get()
            ->keyBy(fn ($r) => $this->groupKey($r));
        $prev = fn (string $group) => $this->bookingsIn($this->prevFrom, $this->prevTo)
            ->groupBy(...$this->groupCols($group))
            ->selectRaw($this->groupSelect($group) . ', ' . $this->gmvSql() . ' as gmv')
            ->get()
            ->keyBy(fn ($r) => $this->groupKey($r));
        $online = fn (string $group) => $this->onlinePayments($this->from, $this->to)
            ->groupBy(...$this->groupCols($group))
            ->selectRaw($this->groupSelect($group) . ', coalesce(sum(p.amount), 0) as amount')
            ->get()
            ->keyBy(fn ($r) => $this->groupKey($r));
        $salons = fn (string $group) => $this->scoped(DB::table('salons as s'))
            ->where('s.status', 'active')
            ->whereNull('s.deleted_at')
            ->groupBy(...$this->groupCols($group))
            ->selectRaw($this->groupSelect($group) . ', count(*) as n')
            ->get()
            ->keyBy(fn ($r) => $this->groupKey($r));
        // Where customers live, from their profile, as demand next to supply.
        $living = fn (string $group) => DB::table('users as s')
            ->where('s.role', 'customer')
            ->whereNull('s.deleted_at')
            ->when($this->cityId, fn ($q) => $q->where('s.city_id', $this->cityId))
            ->when($this->subAreaId, fn ($q) => $q->where('s.sub_area_id', $this->subAreaId))
            ->groupBy(...$this->groupCols($group))
            ->selectRaw($this->groupSelect($group) . ', count(*) as n')
            ->get()
            ->keyBy(fn ($r) => $this->groupKey($r));

        $build = function (string $group) use ($cur, $prev, $online, $salons, $living) {
            $c = $cur($group);
            $p = $prev($group);
            $o = $online($group);
            $sa = $salons($group);
            $l = $living($group);
            $keys = collect([$c, $sa, $l, $p])->flatMap(fn ($set) => $set->keys())->unique()->values();

            $cityIds = $keys->map(fn ($k) => explode('|', $k)[0])->filter()->unique()->values();
            $areaIds = $keys->map(fn ($k) => explode('|', $k)[1] ?? '')->filter()->unique()->values();
            $cityNames = $cityIds->isEmpty() ? collect() : DB::table('cities')->whereIn('id', $cityIds)->pluck('name', 'id');
            $areaNames = $areaIds->isEmpty() ? collect() : DB::table('sub_areas')->whereIn('id', $areaIds)->pluck('name', 'id');

            return $keys->map(function ($key) use ($c, $p, $o, $sa, $l, $cityNames, $areaNames, $group) {
                [$cityId, $areaId] = array_pad(explode('|', $key), 2, '');
                $row = $c[$key] ?? null;
                $bookings = (int) ($row->bookings ?? 0);
                $completed = (int) ($row->completed ?? 0);
                $gmv = $this->r($row->gmv ?? 0);
                $prevGmv = $this->r($p[$key]->gmv ?? 0);
                $salonCount = (int) ($sa[$key]->n ?? 0);
                $customersLiving = (int) ($l[$key]->n ?? 0);

                $out = [
                    'id' => $group === 'area' ? ($areaId ?: null) : ($cityId ?: null),
                    'city_id' => $cityId ?: null,
                    'city' => $cityNames[$cityId] ?? 'No city',
                    'salons' => $salonCount,
                    'bookings' => $bookings,
                    'completed' => $completed,
                    'cancelled' => (int) ($row->cancelled ?? 0),
                    'no_show' => (int) ($row->no_show ?? 0),
                    'gmv' => $gmv,
                    'previous_gmv' => $prevGmv,
                    'growth' => $this->growth($gmv, $prevGmv),
                    'avg_ticket' => $completed > 0 ? $this->r($gmv / $completed) : 0,
                    'cancellation_rate' => $this->pct((int) ($row->cancelled ?? 0), $bookings),
                    'no_show_rate' => $this->pct((int) ($row->no_show ?? 0), $bookings),
                    'customers' => (int) ($row->customers ?? 0),
                    'online_collected' => $this->r($o[$key]->amount ?? 0),
                    'customers_living' => $customersLiving,
                    'customers_per_salon' => $salonCount > 0 ? round($customersLiving / $salonCount, 1) : null,
                    'gmv_per_salon' => $salonCount > 0 ? $this->r($gmv / $salonCount) : 0,
                ];
                if ($group === 'area') {
                    $out = ['name' => $areaId ? ($areaNames[$areaId] ?? 'Unknown area') : 'No area set'] + $out;
                } else {
                    $out = ['name' => $out['city']] + $out;
                }

                return $out;
            })
                ->filter(fn ($r) => $r['bookings'] > 0 || $r['salons'] > 0 || $r['previous_gmv'] > 0)
                ->sortByDesc('gmv')->values()->all();
        };

        $cities = $build('city');
        $areas = $build('area');
        $gmvTotal = array_sum(array_column($cities, 'gmv'));
        foreach ($cities as &$c) {
            $c['share'] = $this->pct($c['gmv'], $gmvTotal);
        }
        unset($c);
        foreach ($areas as &$a) {
            $a['share'] = $this->pct($a['gmv'], $gmvTotal);
        }
        unset($a);

        return [
            'cities' => $cities,
            'areas' => $areas,
            'coverage' => [
                'salons_with_area' => (int) $this->scoped(DB::table('salons as s'))->where('s.status', 'active')->whereNull('s.deleted_at')->whereNotNull('s.sub_area_id')->count(),
                'salons_active' => (int) $this->scoped(DB::table('salons as s'))->where('s.status', 'active')->whereNull('s.deleted_at')->count(),
            ],
        ];
    }

    // ================================================================== salons

    private function salons(): array
    {
        $cur = $this->bookingsIn($this->from, $this->to)
            ->groupBy('a.salon_id')
            ->selectRaw('a.salon_id, ' . $this->statusSql() . ', count(distinct case when a.status = \'completed\' then a.customer_id end) as customers')
            ->get()->keyBy('salon_id');
        $prev = $this->bookingsIn($this->prevFrom, $this->prevTo)
            ->groupBy('a.salon_id')
            ->selectRaw('a.salon_id, ' . $this->gmvSql() . ' as gmv')
            ->pluck('gmv', 'salon_id');
        $online = $this->onlinePayments($this->from, $this->to)
            ->groupBy('a.salon_id')
            ->selectRaw('a.salon_id, coalesce(sum(p.amount), 0) as amount')
            ->pluck('amount', 'salon_id');
        $commission = $this->commissionLines($this->from, $this->to)
            ->groupBy('a.salon_id')
            ->selectRaw('a.salon_id, coalesce(sum(spi.commission_amount), 0) as amount')
            ->pluck('amount', 'salon_id');
        $repeat = DB::query()->fromSub(
            $this->bookingsIn($this->from, $this->to)
                ->where('a.status', 'completed')->whereNotNull('a.customer_id')
                ->groupBy('a.salon_id', 'a.customer_id')
                ->selectRaw('a.salon_id, a.customer_id, count(*) as visits'),
            'x'
        )->groupBy('x.salon_id')
            ->selectRaw('x.salon_id, sum(case when x.visits >= 2 then 1 else 0 end) as repeaters')
            ->pluck('repeaters', 'salon_id');
        $reviews = $this->scoped(DB::table('reviews as rv')->join('salons as s', 's.id', '=', 'rv.salon_id'))
            ->whereBetween('rv.created_at', [$this->from->copy()->startOfDay(), $this->to->copy()->endOfDay()])
            ->groupBy('rv.salon_id')
            ->selectRaw('rv.salon_id, count(*) as n, avg(rv.rating) as avg')
            ->get()->keyBy('salon_id');

        $utilisation = $this->providerUtilisation();
        $bySalon = collect($utilisation)->groupBy('salon_id');

        $ids = $cur->keys()->merge($prev->keys())->map(fn ($id) => (string) $id)->unique();
        $salonRows = $this->scoped(DB::table('salons as s'))
            ->leftJoin('cities as c', 'c.id', '=', 's.city_id')
            ->leftJoin('sub_areas as sa', 'sa.id', '=', 's.sub_area_id')
            ->whereNull('s.deleted_at')
            ->where(fn ($q) => $q->where('s.status', 'active')->orWhereIn('s.id', $ids->all()))
            ->get(['s.id', 's.name', 's.status', 's.commission_opt_in', 's.avg_rating', 's.review_count', 's.approved_at', 'c.name as city', 'sa.name as area']);

        $rows = $salonRows->map(function ($s) use ($cur, $prev, $online, $commission, $repeat, $reviews, $bySalon) {
            $id = (string) $s->id;
            $row = $cur[$id] ?? null;
            $bookings = (int) ($row->bookings ?? 0);
            $completed = (int) ($row->completed ?? 0);
            $upcoming = (int) ($row->upcoming ?? 0);
            $gmv = $this->r($row->gmv ?? 0);
            $prevGmv = $this->r($prev[$id] ?? 0);
            $customers = (int) ($row->customers ?? 0);
            $team = $bySalon->get($id, collect());
            $capacity = (float) $team->sum('capacity_minutes');

            return [
                'id' => $id,
                'name' => $s->name,
                'city' => $s->city ?? 'No city',
                'area' => $s->area,
                'status' => $s->status,
                'billing' => $s->commission_opt_in ? 'Commission Model' : 'Subscription Plan',
                'bookings' => $bookings,
                'completed' => $completed,
                'cancelled' => (int) ($row->cancelled ?? 0),
                'no_show' => (int) ($row->no_show ?? 0),
                'upcoming' => $upcoming,
                'walk_in' => (int) ($row->walk_in ?? 0),
                'completion_rate' => $this->pct($completed, $bookings - $upcoming),
                'cancellation_rate' => $this->pct((int) ($row->cancelled ?? 0), $bookings),
                'no_show_rate' => $this->pct((int) ($row->no_show ?? 0), $bookings),
                'gmv' => $gmv,
                'previous_gmv' => $prevGmv,
                'growth' => $this->growth($gmv, $prevGmv),
                'avg_ticket' => $completed > 0 ? $this->r($gmv / $completed) : 0,
                'online_collected' => $this->r($online[$id] ?? 0),
                'commission' => $this->r($commission[$id] ?? 0),
                'customers' => $customers,
                'repeat_customers' => (int) ($repeat[$id] ?? 0),
                'repeat_rate' => $this->pct((int) ($repeat[$id] ?? 0), $customers),
                'reviews' => (int) ($reviews[$id]->n ?? 0),
                'avg_rating' => isset($reviews[$id]) && $reviews[$id]->avg !== null ? round((float) $reviews[$id]->avg, 2) : null,
                'rating_all_time' => $s->avg_rating !== null ? round((float) $s->avg_rating, 2) : null,
                'team' => $team->count(),
                'utilisation' => $capacity > 0 ? $this->pct((float) $team->sum('booked_minutes'), $capacity) : null,
            ];
        })->sortByDesc('gmv')->values()->all();

        $active = array_filter($rows, fn ($r) => $r['status'] === 'active');

        return [
            'salons' => $rows,
            'providers' => collect($utilisation)->sortByDesc('utilisation')->values()->all(),
            'summary' => [
                'active' => count($active),
                'trading' => count(array_filter($rows, fn ($r) => $r['completed'] > 0)),
                'dormant' => count(array_filter($active, fn ($r) => $r['bookings'] === 0)),
                'new_in_range' => (int) $this->scoped(DB::table('salons as s'))
                    ->whereBetween('s.approved_at', [$this->from->copy()->startOfDay(), $this->to->copy()->endOfDay()])->count(),
                'commission_model' => count(array_filter($active, fn ($r) => $r['billing'] === 'Commission Model')),
                'subscription_plan' => count(array_filter($active, fn ($r) => $r['billing'] === 'Subscription Plan')),
                'pending_approval' => (int) $this->scoped(DB::table('salons as s'))->where('s.status', 'pending_approval')->whereNull('s.deleted_at')->count(),
            ],
        ];
    }

    /**
     * Booked minutes against working minutes for every active team member in
     * scope. Working minutes come from the weekly schedule (the member's own,
     * or the salon's hours when they follow them) for each date in the range,
     * less approved full-day leave. Bookings count when completed, upcoming or
     * in the chair — a cancelled slot was not worked.
     *
     * @return array<int, array>
     */
    private function providerUtilisation(): array
    {
        $providers = $this->scoped(DB::table('service_providers as sp')->join('salons as s', 's.id', '=', 'sp.salon_id'))
            ->leftJoin('users as u', 'u.id', '=', 'sp.user_id')
            ->where('sp.is_active', true)
            ->whereNull('sp.deleted_at')
            ->whereNull('s.deleted_at')
            ->get(['sp.id', 'sp.salon_id', 'sp.use_salon_hours', 'sp.specialization', 'u.name', 's.name as salon']);

        if ($providers->isEmpty()) {
            return [];
        }

        $providerIds = $providers->pluck('id')->map(fn ($id) => (string) $id)->all();
        $salonIds = $providers->pluck('salon_id')->map(fn ($id) => (string) $id)->unique()->values()->all();

        $own = DB::table('provider_working_hours')->whereIn('provider_id', $providerIds)->get()->groupBy('provider_id');
        $salonHours = DB::table('salon_working_hours')->whereIn('salon_id', $salonIds)->get()->groupBy('salon_id');
        $leaves = DB::table('provider_leaves')
            ->whereIn('provider_id', $providerIds)
            ->where('status', 'approved')
            ->where('is_full_day', true)
            ->whereBetween('leave_date', [$this->from->toDateString(), $this->to->toDateString()])
            ->get(['provider_id', 'leave_date'])
            ->groupBy('provider_id');

        $pidSql = 'coalesce(l.serving_provider_id, a.serving_provider_id, a.appointed_provider_id)';
        $booked = $this->linesIn($this->from, $this->to)
            ->whereIn('a.status', ['completed', 'scheduled', 'in_progress'])
            ->groupByRaw($pidSql)
            ->selectRaw("{$pidSql} as pid, coalesce(sum(l.duration_minutes_at_booking), 0) as minutes, count(*) as services, coalesce(sum(case when a.status = 'completed' then l.price_at_booking else 0 end), 0) as revenue")
            ->get()
            ->keyBy('pid');

        $dayCounts = $this->weekdayCounts();
        $minutes = fn (?string $start, ?string $end) => $start && $end
            ? max(0, (strtotime('1970-01-01 ' . substr($end, 0, 8)) - strtotime('1970-01-01 ' . substr($start, 0, 8))) / 60)
            : 0;

        return $providers->map(function ($p) use ($own, $salonHours, $leaves, $booked, $dayCounts, $minutes) {
            $id = (string) $p->id;
            $perDow = array_fill(0, 7, 0.0);
            if ($p->use_salon_hours || ! isset($own[$id])) {
                foreach ($salonHours[(string) $p->salon_id] ?? [] as $h) {
                    if (! $h->is_closed) {
                        $perDow[(int) $h->day_of_week] = $minutes($h->open_time, $h->close_time);
                    }
                }
            } else {
                foreach ($own[$id] as $h) {
                    if (! $h->is_weekly_off) {
                        $perDow[(int) $h->day_of_week] = max(0, $minutes($h->shift_start, $h->shift_end) - $minutes($h->break_start, $h->break_end));
                    }
                }
            }

            $capacity = 0.0;
            foreach ($perDow as $dow => $m) {
                $capacity += $m * $dayCounts[$dow];
            }
            foreach ($leaves[$id] ?? [] as $leave) {
                $capacity -= $perDow[Carbon::parse(substr((string) $leave->leave_date, 0, 10))->dayOfWeek];
            }
            $capacity = max(0, $capacity);
            $b = $booked[$id] ?? null;
            $bookedMinutes = (float) ($b->minutes ?? 0);

            return [
                'id' => $id,
                'name' => $p->name ?? 'Team member',
                'specialization' => $p->specialization,
                'salon_id' => (string) $p->salon_id,
                'salon' => $p->salon,
                'services' => (int) ($b->services ?? 0),
                'revenue' => $this->r($b->revenue ?? 0),
                'booked_minutes' => (int) round($bookedMinutes),
                'capacity_minutes' => (int) round($capacity),
                'leave_days' => count($leaves[$id] ?? []),
                'utilisation' => $capacity > 0 ? $this->pct($bookedMinutes, $capacity) : null,
            ];
        })->values()->all();
    }

    // ================================================================= catalog

    private function catalog(): array
    {
        $lineSql = "count(*) as lines, sum(case when a.status = 'completed' then 1 else 0 end) as completed, coalesce(sum(case when a.status = 'completed' then l.price_at_booking else 0 end), 0) as revenue, coalesce(sum(case when a.status = 'completed' then coalesce(l.original_service_price, l.price_at_booking) - l.price_at_booking else 0 end), 0) as discount";

        $categories = $this->linesIn($this->from, $this->to)
            ->leftJoin('services as sv', 'sv.id', '=', 'l.service_id')
            ->leftJoin('service_templates as st', 'st.id', '=', 'sv.template_id')
            ->leftJoin('service_categories as sc', 'sc.id', '=', 'st.category_id')
            ->groupBy('sc.name')
            ->selectRaw('sc.name as name, ' . $lineSql)
            ->get();
        $catTotal = (float) $categories->sum('revenue');
        $categories = $categories->map(fn ($r) => [
            'name' => $r->name ?? 'Uncategorised',
            'lines' => (int) $r->lines,
            'completed' => (int) $r->completed,
            'revenue' => $this->r($r->revenue),
            'avg_price' => (int) $r->completed > 0 ? $this->r((float) $r->revenue / (int) $r->completed) : 0,
            'share' => $this->pct((float) $r->revenue, $catTotal),
        ])->sortByDesc('revenue')->values()->all();

        $serviceQuery = fn (Carbon $from, Carbon $to) => $this->linesIn($from, $to)
            ->join('services as sv', 'sv.id', '=', 'l.service_id')
            ->join('service_templates as st', 'st.id', '=', 'sv.template_id')
            ->leftJoin('service_categories as sc', 'sc.id', '=', 'st.category_id');
        $prevServices = $serviceQuery($this->prevFrom, $this->prevTo)
            ->groupBy('st.id')
            ->selectRaw("st.id, coalesce(sum(case when a.status = 'completed' then l.price_at_booking else 0 end), 0) as revenue")
            ->pluck('revenue', 'id');
        $services = $serviceQuery($this->from, $this->to)
            ->groupBy('st.id', 'st.name', 'sc.name')
            ->selectRaw('st.id, st.name, sc.name as category, count(distinct a.salon_id) as salons, avg(l.duration_minutes_at_booking) as minutes, ' . $lineSql)
            ->get()
            ->map(function ($r) use ($prevServices) {
                $revenue = $this->r($r->revenue);
                $prev = $this->r($prevServices[(string) $r->id] ?? 0);

                return [
                    'id' => (string) $r->id,
                    'name' => $r->name,
                    'category' => $r->category ?? 'Uncategorised',
                    'lines' => (int) $r->lines,
                    'completed' => (int) $r->completed,
                    'revenue' => $revenue,
                    'previous_revenue' => $prev,
                    'growth' => $this->growth($revenue, $prev),
                    'avg_price' => (int) $r->completed > 0 ? $this->r($revenue / (int) $r->completed) : 0,
                    'discount' => $this->r($r->discount),
                    'salons' => (int) $r->salons,
                    'avg_minutes' => $r->minutes !== null ? (int) round((float) $r->minutes) : null,
                    'revenue_per_hour' => $r->minutes && (int) $r->completed > 0 ? $this->r(($revenue / (int) $r->completed) / ((float) $r->minutes / 60)) : null,
                ];
            })->sortByDesc('revenue')->values()->all();

        $combos = $this->linesIn($this->from, $this->to)
            ->join('combos as cb', 'cb.id', '=', 'l.combo_id')
            ->groupBy('cb.id', 'cb.name', 's.name')
            ->selectRaw("cb.id, cb.name, s.name as salon, count(distinct a.id) as bookings, count(distinct case when a.status = 'completed' then a.id end) as completed, " . $lineSql)
            ->get()
            ->map(fn ($r) => [
                'id' => (string) $r->id,
                'name' => $r->name,
                'salon' => $r->salon,
                'bookings' => (int) $r->bookings,
                'completed' => (int) $r->completed,
                'revenue' => $this->r($r->revenue),
                'discount' => $this->r($r->discount),
            ])->sortByDesc('revenue')->values()->all();
        $comboShare = $this->linesIn($this->from, $this->to)
            ->selectRaw('count(distinct a.id) as bookings, count(distinct case when l.combo_id is not null then a.id end) as with_combo')
            ->first();

        $offers = $this->scoped(DB::table('first_time_offer_redemptions as fr')->join('salons as s', 's.id', '=', 'fr.salon_id'))
            ->leftJoin('first_time_offers as fo', 'fo.id', '=', 'fr.offer_id')
            ->leftJoin('appointments as a', 'a.id', '=', 'fr.appointment_id')
            ->whereBetween('fr.created_at', [$this->from->copy()->startOfDay(), $this->to->copy()->endOfDay()])
            ->groupBy('fo.id', 'fo.name', 'fo.discount_type', 'fo.discount_value')
            ->selectRaw("fo.id, fo.name, fo.discount_type, fo.discount_value, count(*) as n, sum(case when fr.status = 'committed' then 1 else 0 end) as committed, sum(case when fr.status = 'reserved' then 1 else 0 end) as reserved, sum(case when fr.status = 'released' then 1 else 0 end) as released, coalesce(sum(case when fr.status = 'committed' then fr.discount_amount else 0 end), 0) as discount, coalesce(sum(case when a.status = 'completed' then coalesce(a.final_billed_amount, a.total_amount, 0) else 0 end), 0) as gmv")
            ->get()
            ->map(fn ($r) => [
                'id' => $r->id ? (string) $r->id : null,
                'name' => $r->name ?? 'Offer',
                'discount_label' => $r->discount_type === 'percentage' ? rtrim(rtrim((string) $r->discount_value, '0'), '.') . '% off' : '₹' . rtrim(rtrim((string) $r->discount_value, '0'), '.') . ' off',
                'redemptions' => (int) $r->n,
                'committed' => (int) $r->committed,
                'reserved' => (int) $r->reserved,
                'released' => (int) $r->released,
                'discount_given' => $this->r($r->discount),
                'gmv' => $this->r($r->gmv),
                'return_on_discount' => (float) $r->discount > 0 ? round((float) $r->gmv / (float) $r->discount, 1) : null,
            ])->sortByDesc('redemptions')->values()->all();

        $additions = $this->scoped(DB::table('appointment_service_additions as ad')
            ->join('appointments as a', 'a.id', '=', 'ad.appointment_id')
            ->join('salons as s', 's.id', '=', 'a.salon_id'))
            ->leftJoin('services as sv', 'sv.id', '=', 'ad.service_id')
            ->leftJoin('service_templates as st', 'st.id', '=', 'sv.template_id')
            ->whereBetween('a.appointment_date', [$this->from->toDateString(), $this->to->toDateString()])
            ->where('ad.status', '!=', 'removed')
            ->groupBy('st.name')
            ->selectRaw('st.name as name, count(*) as n, coalesce(sum(ad.price_at_addition), 0) as revenue')
            ->orderByDesc('n')
            ->get();

        return [
            'categories' => $categories,
            'services' => $services,
            'combos' => $combos,
            'combo_share' => [
                'bookings' => (int) ($comboShare->bookings ?? 0),
                'with_combo' => (int) ($comboShare->with_combo ?? 0),
                'rate' => $this->pct((int) ($comboShare->with_combo ?? 0), (int) ($comboShare->bookings ?? 0)),
            ],
            'offers' => $offers,
            'offer_totals' => [
                'redemptions' => array_sum(array_column($offers, 'redemptions')),
                'committed' => array_sum(array_column($offers, 'committed')),
                'discount_given' => $this->r(array_sum(array_column($offers, 'discount_given'))),
                'gmv' => $this->r(array_sum(array_column($offers, 'gmv'))),
            ],
            'additions' => [
                'count' => (int) $additions->sum('n'),
                'revenue' => $this->r($additions->sum('revenue')),
                'top' => $additions->take(8)->map(fn ($r) => ['name' => $r->name ?? 'Service', 'count' => (int) $r->n, 'revenue' => $this->r($r->revenue)])->values()->all(),
            ],
        ];
    }

    // =============================================================== customers

    private function customers(): array
    {
        $summary = fn (Carbon $from, Carbon $to) => $this->customerSummary($from, $to);

        // New vs returning per bucket: distinct customer-days, de-duplicated
        // per bucket in PHP (bounded by visits in the range).
        $firsts = $this->firstVisits();
        $pairs = $this->bookingsIn($this->from, $this->to)
            ->where('a.status', 'completed')->whereNotNull('a.customer_id')
            ->joinSub($firsts, 'f', 'f.customer_id', '=', 'a.customer_id')
            ->distinct()
            ->get(['a.customer_id', 'a.appointment_date as d', 'f.first_date']);
        $byBucket = [];
        foreach ($pairs as $row) {
            $key = $this->bucketKey(substr((string) $row->d, 0, 10));
            $isNew = substr((string) $row->first_date, 0, 10) >= $this->from->toDateString()
                && $this->bucketKey(substr((string) $row->first_date, 0, 10)) === $key;
            $byBucket[$key][$isNew ? 'new' : 'returning'][(string) $row->customer_id] = true;
        }
        $trend = [];
        foreach ($this->bucketList() as $key => $label) {
            $trend[] = [
                'date' => $key,
                'label' => $label,
                'new' => count($byBucket[$key]['new'] ?? []),
                'returning' => count(array_diff_key($byBucket[$key]['returning'] ?? [], $byBucket[$key]['new'] ?? [])),
            ];
        }

        // Per customer in the range: visits and spend.
        $per = $this->bookingsIn($this->from, $this->to)
            ->where('a.status', 'completed')->whereNotNull('a.customer_id')
            ->groupBy('a.customer_id')
            ->selectRaw('a.customer_id, count(*) as visits, ' . $this->gmvSql() . ' as spend, count(distinct a.salon_id) as salons, max(a.appointment_date) as last_visit')
            ->get();
        $frequency = ['1 visit' => 0, '2 visits' => 0, '3–5 visits' => 0, '6+ visits' => 0];
        $spendBands = ['Under ₹500' => 0, '₹500–1,000' => 0, '₹1,000–2,500' => 0, '₹2,500–5,000' => 0, '₹5,000+' => 0];
        foreach ($per as $c) {
            $v = (int) $c->visits;
            $frequency[$v === 1 ? '1 visit' : ($v === 2 ? '2 visits' : ($v <= 5 ? '3–5 visits' : '6+ visits'))]++;
            $s = (float) $c->spend;
            $spendBands[$s < 500 ? 'Under ₹500' : ($s < 1000 ? '₹500–1,000' : ($s < 2500 ? '₹1,000–2,500' : ($s < 5000 ? '₹2,500–5,000' : '₹5,000+')))]++;
        }
        $multiSalon = $per->filter(fn ($c) => (int) $c->salons > 1)->count();

        $topIds = $per->sortByDesc(fn ($c) => (float) $c->spend)->take(15);
        $users = $topIds->isEmpty() ? collect() : DB::table('users')->whereIn('id', $topIds->pluck('customer_id')->all())->get(['id', 'name', 'phone', 'gender'])->keyBy('id');
        $top = $topIds->map(fn ($c) => [
            'id' => (string) $c->customer_id,
            'name' => $users[(string) $c->customer_id]->name ?? 'Customer',
            'phone' => isset($users[(string) $c->customer_id]) && $users[(string) $c->customer_id]->phone ? '••••' . substr((string) $users[(string) $c->customer_id]->phone, -4) : null,
            'visits' => (int) $c->visits,
            'spend' => $this->r($c->spend),
            'salons' => (int) $c->salons,
            'last_visit' => substr((string) $c->last_visit, 0, 10),
        ])->values()->all();

        // Cohorts: customers grouped by the month of their first visit in
        // scope, and the share who came back in each month after.
        $monthSql = 'substr(cast(a.appointment_date as varchar), 1, 7)';
        $cohortSql = 'substr(cast(f.first_date as varchar), 1, 7)';
        $endMonth = $this->to->copy()->startOfMonth();
        $startMonth = $endMonth->copy()->subMonthsNoOverflow(5);
        $activity = $this->scoped(DB::table('appointments as a')->join('salons as s', 's.id', '=', 'a.salon_id'))
            ->where('a.status', 'completed')->whereNotNull('a.customer_id')
            ->joinSub($firsts, 'f', 'f.customer_id', '=', 'a.customer_id')
            ->where('f.first_date', '>=', $startMonth->toDateString())
            ->where('a.appointment_date', '<=', $this->to->toDateString())
            ->groupByRaw("{$cohortSql}, {$monthSql}")
            ->selectRaw("{$cohortSql} as cohort, {$monthSql} as m, count(distinct a.customer_id) as n")
            ->get();
        $cohorts = [];
        $cursor = $startMonth->copy();
        while ($cursor->lte($endMonth)) {
            $key = $cursor->format('Y-m');
            $rows = $activity->where('cohort', $key)->keyBy('m');
            $size = (int) ($rows[$key]->n ?? 0);
            $retention = [];
            $probe = $cursor->copy();
            for ($i = 0; $probe->lte($endMonth) && $i < 6; $i++) {
                $n = (int) ($rows[$probe->format('Y-m')]->n ?? 0);
                $retention[] = ['offset' => $i, 'customers' => $n, 'rate' => $this->pct($n, $size)];
                $probe->addMonthNoOverflow();
            }
            $cohorts[] = ['cohort' => $key, 'label' => $cursor->format('M Y'), 'size' => $size, 'retention' => $retention];
            $cursor->addMonthNoOverflow();
        }

        $gender = $this->bookingsIn($this->from, $this->to)
            ->where('a.status', 'completed')
            ->leftJoin('users as cu', 'cu.id', '=', 'a.customer_id')
            ->groupByRaw("coalesce(a.recipient_gender, cu.gender, a.walk_in_customer_gender, 'unknown')")
            ->selectRaw("coalesce(a.recipient_gender, cu.gender, a.walk_in_customer_gender, 'unknown') as g, count(*) as visits, " . $this->gmvSql() . ' as gmv')
            ->get()
            ->map(fn ($r) => ['gender' => ucfirst((string) $r->g), 'visits' => (int) $r->visits, 'gmv' => $this->r($r->gmv)])
            ->sortByDesc('visits')->values()->all();

        $signupsQ = DB::table('users as u')->where('u.role', 'customer')
            ->when($this->cityId, fn ($q) => $q->where('u.city_id', $this->cityId))
            ->when($this->subAreaId, fn ($q) => $q->where('u.sub_area_id', $this->subAreaId))
            ->whereBetween('u.created_at', [$this->from->copy()->startOfDay(), $this->to->copy()->endOfDay()]);
        $signupTrend = $this->series(['signups' => $this->perDay((clone $signupsQ), 'u.created_at', 'count(*)')]);
        $signups = (int) (clone $signupsQ)->count();
        $signupsBooked = (int) (clone $signupsQ)->whereExists(fn ($q) => $q->selectRaw('1')->from('appointments as a')->whereColumn('a.customer_id', 'u.id')->where('a.status', '!=', 'pending_payment'))->count();

        return [
            'summary' => ['current' => $summary($this->from, $this->to), 'previous' => $summary($this->prevFrom, $this->prevTo)],
            'trend' => $trend,
            'frequency' => collect($frequency)->map(fn ($n, $l) => ['label' => $l, 'customers' => $n])->values()->all(),
            'spend_bands' => collect($spendBands)->map(fn ($n, $l) => ['label' => $l, 'customers' => $n])->values()->all(),
            'multi_salon_customers' => $multiSalon,
            'top' => $top,
            'cohorts' => $cohorts,
            'gender' => $gender,
            'signups' => [
                'total' => $signups,
                'booked' => $signupsBooked,
                'conversion' => $this->pct($signupsBooked, $signups),
                'trend' => array_map(fn ($p) => ['date' => $p['date'], 'label' => $p['label'], 'signups' => (int) $p['signups']], $signupTrend),
            ],
        ];
    }

    private function customerSummary(Carbon $from, Carbon $to): array
    {
        $row = $this->bookingsIn($from, $to)
            ->where('a.status', 'completed')
            ->selectRaw('count(distinct a.customer_id) as customers, count(case when a.customer_id is not null then 1 end) as visits, coalesce(sum(case when a.customer_id is not null then coalesce(a.final_billed_amount, a.total_amount, 0) else 0 end), 0) as spend, count(distinct a.walk_in_customer_phone) as walk_ins')
            ->first();
        $repeaters = (int) DB::query()->fromSub(
            $this->bookingsIn($from, $to)->where('a.status', 'completed')->whereNotNull('a.customer_id')
                ->groupBy('a.customer_id')->havingRaw('count(*) >= 2')->selectRaw('a.customer_id'),
            'x'
        )->count();
        $customers = (int) $row->customers;
        $new = $this->newCustomers($from, $to);

        return [
            'customers' => $customers,
            'new' => $new,
            'returning' => max(0, $customers - $new),
            'repeaters' => $repeaters,
            'repeat_rate' => $this->pct($repeaters, $customers),
            'visits' => (int) $row->visits,
            'visits_per_customer' => $customers > 0 ? round((int) $row->visits / $customers, 2) : 0,
            'spend_per_customer' => $customers > 0 ? $this->r((float) $row->spend / $customers) : 0,
            'walk_in_customers' => (int) $row->walk_ins,
        ];
    }

    /** Each customer's first completed visit within the city/area scope. */
    private function firstVisits(): Builder
    {
        return $this->scoped(DB::table('appointments as fa')->join('salons as s', 's.id', '=', 'fa.salon_id'))
            ->where('fa.status', 'completed')
            ->whereNotNull('fa.customer_id')
            ->groupBy('fa.customer_id')
            ->selectRaw('fa.customer_id, min(fa.appointment_date) as first_date');
    }

    private function newCustomers(Carbon $from, Carbon $to): int
    {
        return (int) DB::query()->fromSub($this->firstVisits(), 'f')
            ->whereBetween('f.first_date', [$from->toDateString(), $to->toDateString()])
            ->count();
    }

    // ============================================================== engagement

    private function engagement(): array
    {
        $start = $this->from->copy()->startOfDay();
        $end = $this->to->copy()->endOfDay();
        $filtered = $this->cityId || $this->subAreaId;

        $reviewsQ = fn () => $this->scoped(DB::table('reviews as rv')->join('salons as s', 's.id', '=', 'rv.salon_id'))
            ->whereBetween('rv.created_at', [$start, $end]);
        $dist = $reviewsQ()->groupBy('rv.rating')->selectRaw('rv.rating, count(*) as n')->pluck('n', 'rating');
        $reviewTotals = $reviewsQ()->selectRaw('count(*) as n, avg(rv.rating) as avg')->first();
        $ratingTrend = $this->series([
            'reviews' => $this->perDay($reviewsQ(), 'rv.created_at', 'count(*)'),
            'rating_sum' => $this->perDay($reviewsQ(), 'rv.created_at', 'sum(rv.rating)'),
        ]);
        foreach ($ratingTrend as &$p) {
            $p['avg_rating'] = $p['reviews'] > 0 ? round($p['rating_sum'] / $p['reviews'], 2) : null;
            unset($p['rating_sum']);
        }
        unset($p);
        $lowest = $reviewsQ()->groupBy('s.id', 's.name')
            ->havingRaw('count(*) >= 3')
            ->selectRaw('s.id, s.name, count(*) as n, avg(rv.rating) as avg')
            ->orderBy('avg')->limit(6)->get()
            ->map(fn ($r) => ['id' => (string) $r->id, 'name' => $r->name, 'reviews' => (int) $r->n, 'avg_rating' => round((float) $r->avg, 2)])
            ->all();
        $completed = (int) $this->bookingsIn($this->from, $this->to)->where('a.status', 'completed')->count();

        $complaintsQ = fn () => $this->scoped(DB::table('complaints as cp')->join('salons as s', 's.id', '=', 'cp.salon_id'))
            ->whereBetween('cp.created_at', [$start, $end]);
        $complaintStatus = $complaintsQ()->groupBy('cp.status')->selectRaw('cp.status, count(*) as n')->pluck('n', 'status')->map(fn ($n) => (int) $n)->all();
        $resolved = $complaintsQ()->whereNotNull('cp.resolved_at')->get(['cp.created_at', 'cp.resolved_at']);
        $avgResolution = $resolved->isEmpty() ? null : round($resolved->avg(fn ($r) => Carbon::parse($r->created_at)->diffInMinutes(Carbon::parse($r->resolved_at)) / 60), 1);

        $campaignsQ = fn () => $this->scoped(DB::table('campaigns as cm')->join('salons as s', 's.id', '=', 'cm.salon_id'))
            ->whereBetween('cm.created_at', [$start, $end]);
        $campaignTotals = $campaignsQ()->selectRaw('count(*) as n, coalesce(sum(cm.recipients_count), 0) as recipients, coalesce(sum(cm.sent_count), 0) as sent, coalesce(sum(cm.delivered_count), 0) as delivered, coalesce(sum(cm.read_count), 0) as read_n, coalesce(sum(cm.failed_count), 0) as failed, coalesce(sum(cm.skipped_count), 0) as skipped, count(distinct cm.salon_id) as salons')->first();
        $campaignStatus = $campaignsQ()->groupBy('cm.status')->selectRaw('cm.status, count(*) as n')->pluck('n', 'status')->map(fn ($n) => (int) $n)->all();
        $byTemplate = $campaignsQ()->leftJoin('campaign_templates as ct', 'ct.id', '=', 'cm.campaign_template_id')
            ->groupBy('ct.name')
            ->selectRaw('ct.name as name, count(*) as n, coalesce(sum(cm.sent_count), 0) as sent, coalesce(sum(cm.delivered_count), 0) as delivered, coalesce(sum(cm.read_count), 0) as read_n')
            ->orderByDesc('n')->get()
            ->map(fn ($r) => [
                'name' => $r->name ?? 'Custom',
                'campaigns' => (int) $r->n,
                'sent' => (int) $r->sent,
                'delivered' => (int) $r->delivered,
                'read' => (int) $r->read_n,
                'read_rate' => $this->pct((int) $r->read_n, (int) $r->delivered),
            ])->all();
        $topCampaignSalons = $campaignsQ()->groupBy('s.id', 's.name')
            ->selectRaw('s.id, s.name, count(*) as n, coalesce(sum(cm.sent_count), 0) as sent')
            ->orderByDesc('sent')->limit(6)->get()
            ->map(fn ($r) => ['id' => (string) $r->id, 'name' => $r->name, 'campaigns' => (int) $r->n, 'sent' => (int) $r->sent])->all();

        $waQ = DB::table('whatsapp_messages as w')->whereBetween('w.created_at', [$start, $end]);
        if ($filtered) {
            $waQ = $this->scoped($waQ->join('salons as s', 's.id', '=', 'w.related_salon_id'));
        }
        $wa = (clone $waQ)->groupBy('w.category', 'w.status')->selectRaw('w.category, w.status, count(*) as n')->get();
        $waByCategory = $wa->groupBy(fn ($r) => $r->category ?: 'other')->map(function ($g, $cat) {
            $count = fn (array $s) => (int) $g->whereIn('status', $s)->sum('n');
            $total = (int) $g->sum('n');
            $delivered = $count(['delivered', 'read']);

            return [
                'category' => ucfirst((string) $cat),
                'total' => $total,
                'sent' => $count(['sent', 'delivered', 'read']),
                'delivered' => $delivered,
                'read' => $count(['read']),
                'failed' => $count(['failed']),
                'delivery_rate' => $this->pct($delivered, $total),
            ];
        })->sortByDesc('total')->values()->all();
        $waTrend = $this->series(['messages' => $this->perDay(clone $waQ, 'w.created_at', 'count(*)')]);

        $coins = $this->scoped(DB::table('wallet_transactions as wt')->join('salons as s', 's.id', '=', 'wt.salon_id'))
            ->whereBetween('wt.created_at', [$start, $end])
            ->groupBy('wt.type')
            ->selectRaw('wt.type, count(*) as n, coalesce(sum(wt.coins), 0) as coins, coalesce(sum(wt.coins * coalesce(wt.coin_value_snapshot, 0)), 0) as value')
            ->get()
            ->map(fn ($r) => [
                'type' => $r->type,
                'label' => match ($r->type) {
                    'earned' => 'Earned on bookings',
                    'redeemed' => 'Spent (commission, plans)',
                    'expired' => 'Expired',
                    'welcome_bonus' => 'Welcome bonus',
                    'adjustment' => 'Manual adjustment',
                    default => ucfirst(str_replace('_', ' ', (string) $r->type)),
                },
                'transactions' => (int) $r->n,
                'coins' => (int) round((float) $r->coins),
                'value' => $this->r(abs((float) $r->value)),
            ])->values()->all();
        $balance = $this->scoped(DB::table('salon_wallets as sw')->join('salons as s', 's.id', '=', 'sw.salon_id'))
            ->selectRaw('coalesce(sum(sw.coin_balance), 0) as coins, count(*) as wallets')->first();

        $notifQ = DB::table('notifications as n')->whereBetween('n.created_at', [$start, $end]);
        if ($filtered) {
            $notifQ = $this->scoped($notifQ->join('salons as s', 's.id', '=', 'n.related_salon_id'));
        }
        $notif = $notifQ->selectRaw('count(*) as n, sum(case when n.read_at is not null then 1 else 0 end) as read_n')->first();

        return [
            'reviews' => [
                'count' => (int) $reviewTotals->n,
                'avg_rating' => $reviewTotals->avg !== null ? round((float) $reviewTotals->avg, 2) : null,
                'review_rate' => $this->pct((int) $reviewTotals->n, $completed),
                'distribution' => array_map(fn ($star) => ['stars' => $star, 'count' => (int) ($dist[$star] ?? 0)], [5, 4, 3, 2, 1]),
                'trend' => $ratingTrend,
                'lowest_rated' => $lowest,
            ],
            'complaints' => [
                'count' => array_sum($complaintStatus),
                'by_status' => $complaintStatus,
                'avg_resolution_hours' => $avgResolution,
                'per_1000_visits' => $completed > 0 ? round(array_sum($complaintStatus) / $completed * 1000, 1) : 0,
            ],
            'campaigns' => [
                'count' => (int) $campaignTotals->n,
                'salons' => (int) $campaignTotals->salons,
                'recipients' => (int) $campaignTotals->recipients,
                'sent' => (int) $campaignTotals->sent,
                'delivered' => (int) $campaignTotals->delivered,
                'read' => (int) $campaignTotals->read_n,
                'failed' => (int) $campaignTotals->failed,
                'skipped' => (int) $campaignTotals->skipped,
                'delivery_rate' => $this->pct((int) $campaignTotals->delivered, (int) $campaignTotals->sent),
                'read_rate' => $this->pct((int) $campaignTotals->read_n, (int) $campaignTotals->delivered),
                'by_status' => $campaignStatus,
                'by_template' => $byTemplate,
                'top_salons' => $topCampaignSalons,
            ],
            'whatsapp' => [
                'total' => array_sum(array_column($waByCategory, 'total')),
                'by_category' => $waByCategory,
                'trend' => $waTrend,
            ],
            'coins' => [
                'by_type' => $coins,
                'balance' => (int) round((float) $balance->coins),
                'wallets' => (int) $balance->wallets,
            ],
            'notifications' => [
                'count' => (int) $notif->n,
                'read' => (int) $notif->read_n,
                'read_rate' => $this->pct((int) $notif->read_n, (int) $notif->n),
            ],
        ];
    }

    // ============================================================== query parts

    private function scope(array $data): void
    {
        $to = ! empty($data['to']) ? Carbon::parse($data['to'])->endOfDay() : Carbon::today()->endOfDay();
        $from = ! empty($data['from']) ? Carbon::parse($data['from'])->startOfDay() : $to->copy()->subDays(29)->startOfDay();
        if ($from->gt($to)) {
            [$from, $to] = [$to->copy()->startOfDay(), $from->copy()->endOfDay()];
        }
        // Two years is plenty for a dashboard, and keeps a daily series sane.
        if ($from->diffInDays($to) > 731) {
            $from = $to->copy()->subDays(730)->startOfDay();
        }

        $this->from = $from;
        $this->to = $to;
        $days = $this->days();
        $this->prevTo = $from->copy()->subDay()->endOfDay();
        $this->prevFrom = $this->prevTo->copy()->subDays($days - 1)->startOfDay();

        $granularity = $data['granularity'] ?? ($days <= 31 ? 'daily' : ($days <= 120 ? 'weekly' : 'monthly'));
        if ($granularity === 'daily' && $days > 186) {
            $granularity = 'weekly';
        }
        $this->granularity = $granularity;
        $this->cityId = ! empty($data['city_id']) ? (string) $data['city_id'] : null;
        $this->subAreaId = ! empty($data['sub_area_id']) ? (string) $data['sub_area_id'] : null;
    }

    private function days(): int
    {
        return (int) $this->from->copy()->startOfDay()->diffInDays($this->to->copy()->startOfDay()) + 1;
    }

    /** Narrow a query joined to `salons as s` to the chosen city and area. */
    private function scoped(Builder $q): Builder
    {
        return $q
            ->when($this->cityId, fn ($w) => $w->where('s.city_id', $this->cityId))
            ->when($this->subAreaId, fn ($w) => $w->where('s.sub_area_id', $this->subAreaId));
    }

    /** Bookings (see class doc) dated inside a window, joined to their salon. */
    private function bookingsIn(Carbon $from, Carbon $to): Builder
    {
        return $this->scoped(DB::table('appointments as a')->join('salons as s', 's.id', '=', 'a.salon_id'))
            ->where('a.appointment_date', '>=', $from->toDateString())
            ->where('a.appointment_date', '<=', $to->toDateString())
            ->where('a.status', '!=', 'pending_payment')
            ->where(fn ($q) => $q->where('a.status', '!=', 'cancelled')
                ->orWhereNull('a.cancelled_by')
                ->orWhere('a.cancelled_by', '!=', 'system'));
    }

    /** Service lines of the bookings in a window. */
    private function linesIn(Carbon $from, Carbon $to): Builder
    {
        return $this->bookingsIn($from, $to)->join('appointment_services as l', 'l.appointment_id', '=', 'a.id');
    }

    /** Successful payments (any channel) paid in a window, joined to booking and salon. */
    private function paymentsBase(Carbon $from, Carbon $to): Builder
    {
        return DB::table('payments as p')
            ->join('appointments as a', 'a.id', '=', 'p.appointment_id')
            ->join('salons as s', 's.id', '=', 'a.salon_id')
            ->where('p.status', 'success')
            ->whereBetween('p.paid_at', [$from->copy()->startOfDay(), $to->copy()->endOfDay()]);
    }

    private function onlinePayments(Carbon $from, Carbon $to): Builder
    {
        return $this->scoped($this->paymentsBase($from, $to))->whereNotNull('p.gateway');
    }

    /** Refunds of gateway money raised in a window (failed ones never left). */
    private function refundsIn(Carbon $from, Carbon $to): Builder
    {
        return $this->scoped(
            DB::table('payment_refunds as r')
                ->join('payments as p', 'p.id', '=', 'r.payment_id')
                ->join('appointments as a', 'a.id', '=', 'r.appointment_id')
                ->join('salons as s', 's.id', '=', 'a.salon_id')
        )->whereNotNull('p.gateway')
            ->where('r.status', '!=', 'failed')
            ->whereBetween('r.created_at', [$from->copy()->startOfDay(), $to->copy()->endOfDay()]);
    }

    /** Commission lines payouts calculated, dated by the visit. */
    private function commissionLines(Carbon $from, Carbon $to): Builder
    {
        return $this->scoped(
            DB::table('salon_payout_items as spi')
                ->join('appointments as a', 'a.id', '=', 'spi.appointment_id')
                ->join('salons as s', 's.id', '=', 'a.salon_id')
        )->where('spi.kind', SalonPayoutItem::KIND_BOOKING)
            ->whereBetween('a.appointment_date', [$from->toDateString(), $to->toDateString()]);
    }

    /** Plan payments SuperAdmin approved in a window. */
    private function planPayments(Carbon $from, Carbon $to): Builder
    {
        return $this->scoped(
            DB::table('subscription_payment_requests as r')
                ->join('salons as s', 's.id', '=', 'r.salon_id')
                ->leftJoin('subscription_plans as plp', 'plp.id', '=', 'r.subscription_plan_id')
        )->where('r.status', 'approved')
            ->whereBetween('r.updated_at', [$from->copy()->startOfDay(), $to->copy()->endOfDay()]);
    }

    private function payoutsDistributed(Carbon $from, Carbon $to): Builder
    {
        return $this->scoped(DB::table('salon_payouts as sp')->join('salons as s', 's.id', '=', 'sp.salon_id'))
            ->where('sp.status', PayoutService::STATUS_DISTRIBUTED)
            ->whereBetween('sp.distributed_at', [$from->copy()->startOfDay(), $to->copy()->endOfDay()]);
    }

    /** Cash a plan payment brought in: after coins, older rows from the plan price. */
    private function planCashSql(): string
    {
        return 'case when r.amount_payable_inr is not null then r.amount_payable_inr when coalesce(plp.price, 0) > coalesce(r.coin_discount_inr, 0) then coalesce(plp.price, 0) - coalesce(r.coin_discount_inr, 0) else 0 end';
    }

    private function gmvSql(): string
    {
        return "coalesce(sum(case when a.status = 'completed' then coalesce(a.final_billed_amount, a.total_amount, 0) else 0 end), 0)";
    }

    private function statusSql(): string
    {
        return "count(*) as bookings,
            sum(case when a.status = 'completed' then 1 else 0 end) as completed,
            sum(case when a.status = 'cancelled' then 1 else 0 end) as cancelled,
            sum(case when a.status = 'no_show' then 1 else 0 end) as no_show,
            sum(case when a.status in ('scheduled', 'in_progress') then 1 else 0 end) as upcoming,
            sum(case when a.booking_source = 'walk_in' or a.walk_in_customer_name is not null then 1 else 0 end) as walk_in,
            " . $this->gmvSql() . ' as gmv';
    }

    private function groupCols(string $group): array
    {
        return $group === 'area' ? ['s.city_id', 's.sub_area_id'] : ['s.city_id'];
    }

    private function groupSelect(string $group): string
    {
        return $group === 'area' ? 's.city_id as gc, s.sub_area_id as ga' : 's.city_id as gc';
    }

    private function groupKey(object $r): string
    {
        return (string) ($r->gc ?? '') . '|' . (string) ($r->ga ?? '');
    }

    private function day(string $column): string
    {
        return "substr(cast({$column} as varchar), 1, 10)";
    }

    /** One aggregate per calendar day: [Y-m-d => value]. */
    private function perDay(Builder $q, string $column, string $aggregate): array
    {
        $day = $this->day($column);

        return $q->groupByRaw($day)
            ->selectRaw("{$day} as d, {$aggregate} as v")
            ->pluck('v', 'd')
            ->map(fn ($v) => (float) $v)
            ->all();
    }

    private function bucketKey(string $date): string
    {
        return match ($this->granularity) {
            'weekly' => Carbon::parse($date)->startOfWeek()->toDateString(),
            'monthly' => substr($date, 0, 7) . '-01',
            default => $date,
        };
    }

    /** Every bucket in the window, empty ones included: [key => label]. */
    private function bucketList(): array
    {
        $cursor = match ($this->granularity) {
            'weekly' => $this->from->copy()->startOfWeek(),
            'monthly' => $this->from->copy()->startOfMonth(),
            default => $this->from->copy()->startOfDay(),
        };
        $out = [];
        while ($cursor->lte($this->to)) {
            $out[$cursor->toDateString()] = match ($this->granularity) {
                'weekly' => $cursor->format('d M'),
                'monthly' => $cursor->format('M Y'),
                default => $cursor->format('d M'),
            };
            match ($this->granularity) {
                'weekly' => $cursor->addWeek(),
                'monthly' => $cursor->addMonthNoOverflow(),
                default => $cursor->addDay(),
            };
        }

        return $out;
    }

    /**
     * Roll per-day figures up into the chart's buckets.
     *
     * @param  array<string, array<string, float>>  $fields  name => [Y-m-d => value]
     */
    private function series(array $fields): array
    {
        $sums = [];
        foreach ($fields as $name => $days) {
            foreach ($days as $day => $v) {
                $key = $this->bucketKey(substr((string) $day, 0, 10));
                $sums[$key][$name] = ($sums[$key][$name] ?? 0) + $v;
            }
        }

        $out = [];
        foreach ($this->bucketList() as $key => $label) {
            $point = ['date' => $key, 'label' => $label];
            foreach (array_keys($fields) as $name) {
                $point[$name] = round($sums[$key][$name] ?? 0, 2);
            }
            $out[] = $point;
        }

        return $out;
    }

    /** How many of each weekday (0 = Sunday) the window holds. */
    private function weekdayCounts(): array
    {
        $counts = array_fill(0, 7, 0);
        $full = intdiv($this->days(), 7);
        for ($d = 0; $d < 7; $d++) {
            $counts[$d] = $full;
        }
        $cursor = $this->from->copy()->addDays($full * 7);
        while ($cursor->lte($this->to)) {
            $counts[$cursor->dayOfWeek]++;
            $cursor->addDay();
        }

        return $counts;
    }

    private function paymentLabel(string $channel, ?string $type, ?string $mode): string
    {
        if ($channel === 'online') {
            return match ($type) {
                'advance' => 'Online · advance',
                'full', 'full_payment' => 'Online · full payment',
                'balance' => 'Online · balance',
                default => 'Online · ' . str_replace('_', ' ', (string) ($type ?: 'payment')),
            };
        }

        return 'At salon · ' . match ($mode) {
            'upi' => 'UPI',
            'cash' => 'cash',
            'card' => 'card',
            default => str_replace('_', ' ', (string) ($mode ?: 'other')),
        };
    }

    private function r(mixed $v): float
    {
        return round((float) $v, 2);
    }

    private function pct(float|int $part, float|int $whole): float
    {
        return $whole > 0 ? round($part / $whole * 100, 1) : 0.0;
    }

    private function growth(float $current, float $previous): ?float
    {
        return $previous > 0 ? round(($current - $previous) / $previous * 100, 1) : null;
    }
}
