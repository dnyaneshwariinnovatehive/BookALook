<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Services\PayoutService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * What BookALook itself earns. It owns no salons, so its income is two things:
 *
 *  - Subscription Plan payments salons make, counted when SuperAdmin approves
 *    them, at the cash actually transferred (after any coins).
 *  - Commission on Commission Model salons, counted once that payout has been
 *    settled — distributed or collected. Commission calculated but not yet
 *    settled is reported apart, as pending.
 *
 * Reward coins are not revenue: what they covered is reported as "coins given
 * away", next to the cash. Amounts are as collected; GST is not split out.
 */
class PlatformRevenueController extends Controller
{
    private const GRANULARITIES = ['daily', 'weekly', 'monthly'];

    public function show(Request $request)
    {
        $request->validate([
            'from' => 'nullable|date',
            'to' => 'nullable|date',
            'granularity' => 'nullable|in:' . implode(',', self::GRANULARITIES),
        ]);

        $to = $request->filled('to') ? Carbon::parse($request->to)->endOfDay() : Carbon::now()->endOfDay();
        $from = $request->filled('from') ? Carbon::parse($request->from)->startOfDay() : $to->copy()->subDays(29)->startOfDay();
        if ($from->gt($to)) {
            [$from, $to] = [$to->copy()->startOfDay(), $from->copy()->endOfDay()];
        }
        $granularity = $request->input('granularity', 'daily');

        $entries = $this->entries($from, $to);

        // The same length of time just before, for the "vs previous" chips.
        $days = (int) $from->diffInDays($to) + 1;
        $prevTo = $from->copy()->subDay()->endOfDay();
        $prevFrom = $prevTo->copy()->subDays($days - 1)->startOfDay();
        $previous = $this->entries($prevFrom, $prevTo);

        return response()->json([
            'success' => true,
            'range' => [
                'from' => $from->toDateString(),
                'to' => $to->toDateString(),
                'granularity' => $granularity,
                'previous_from' => $prevFrom->toDateString(),
                'previous_to' => $prevTo->toDateString(),
            ],
            'totals' => $this->totals($entries),
            'previous_totals' => $this->totals($previous),
            'pending_commission' => $this->pendingCommission(),
            'all_time' => $this->totals($this->entries(null, null)),
            'trend' => $this->trend($entries, $from, $to, $granularity),
            'by_plan' => $this->byPlan($entries),
            'by_city' => $this->group($entries, 'city', 8),
            'top_salons' => $this->group($entries, 'salon', 8, withId: true),
            'recent' => $entries->sortByDesc('at')->take(10)->values()->map(fn ($e) => [
                'kind' => $e['kind'],
                'salon' => $e['salon'],
                'label' => $e['label'],
                'amount' => $e['amount'],
                'coins' => $e['coins'],
                'at' => $e['at']->toIso8601String(),
            ])->all(),
        ]);
    }

    /**
     * Every rupee BookALook received in a window, one entry per payment.
     * Null bounds mean all time.
     *
     * @return Collection<int, array{kind: string, salon_id: string, salon: string, city: string, label: string, amount: float, coins: float, at: Carbon}>
     */
    private function entries(?Carbon $from, ?Carbon $to): Collection
    {
        $subscriptions = DB::table('subscription_payment_requests as r')
            ->join('salons as s', 's.id', '=', 'r.salon_id')
            ->leftJoin('cities as c', 'c.id', '=', 's.city_id')
            ->leftJoin('subscription_plans as p', 'p.id', '=', 'r.subscription_plan_id')
            ->where('r.status', 'approved')
            ->when($from, fn ($q) => $q->where('r.updated_at', '>=', $from))
            ->when($to, fn ($q) => $q->where('r.updated_at', '<=', $to))
            ->get([
                'r.salon_id', 's.name as salon', 'c.name as city', 'p.name as plan', 'p.price as plan_price',
                'r.billing_type', 'r.amount_payable_inr', 'r.coin_discount_inr', 'r.updated_at',
            ])
            ->map(function ($r) {
                $coins = (float) ($r->coin_discount_inr ?? 0);
                // Older requests predate amount_payable_inr: the plan price less
                // any coins is what was transferred.
                $cash = $r->amount_payable_inr !== null
                    ? (float) $r->amount_payable_inr
                    : max(0, (float) ($r->plan_price ?? 0) - $coins);

                return [
                    'kind' => 'subscription',
                    'salon_id' => (string) $r->salon_id,
                    'salon' => $r->salon ?? 'Salon',
                    'city' => $r->city ?? 'No city',
                    'label' => $r->plan ?? ($r->billing_type === 'commission' ? 'Commission Model' : 'Plan'),
                    'amount' => round($cash, 2),
                    'coins' => round($coins, 2),
                    'at' => Carbon::parse($r->updated_at),
                ];
            });

        $commission = DB::table('salon_payouts as sp')
            ->join('salons as s', 's.id', '=', 'sp.salon_id')
            ->leftJoin('cities as c', 'c.id', '=', 's.city_id')
            ->where('sp.status', PayoutService::STATUS_DISTRIBUTED)
            ->where('sp.commission_deducted', '>', 0)
            ->when($from, fn ($q) => $q->where('sp.distributed_at', '>=', $from))
            ->when($to, fn ($q) => $q->where('sp.distributed_at', '<=', $to))
            ->get([
                'sp.salon_id', 's.name as salon', 'c.name as city', 'sp.commission_deducted',
                'sp.wallet_redeemed_amount', 'sp.distributed_at', 'sp.cycle_start_date', 'sp.cycle_type',
            ])
            ->map(function ($p) {
                $coins = min((float) $p->commission_deducted, (float) ($p->wallet_redeemed_amount ?? 0));

                return [
                    'kind' => 'commission',
                    'salon_id' => (string) $p->salon_id,
                    'salon' => $p->salon ?? 'Salon',
                    'city' => $p->city ?? 'No city',
                    'label' => 'Commission · ' . Carbon::parse($p->cycle_start_date)->format($p->cycle_type === 'monthly' ? 'M Y' : 'j M'),
                    'amount' => round((float) $p->commission_deducted - $coins, 2),
                    'coins' => round($coins, 2),
                    'at' => Carbon::parse($p->distributed_at),
                ];
            });

        return $subscriptions->concat($commission)->values();
    }

    private function totals(Collection $entries): array
    {
        $subs = $entries->where('kind', 'subscription');
        $comm = $entries->where('kind', 'commission');
        $total = round($entries->sum('amount'), 2);
        $payers = $entries->where('amount', '>', 0)->pluck('salon_id')->unique()->count();

        return [
            'total' => $total,
            'subscriptions' => round($subs->sum('amount'), 2),
            'subscription_payments' => $subs->count(),
            'commission' => round($comm->sum('amount'), 2),
            'commission_settlements' => $comm->count(),
            'coins_given' => round($entries->sum('coins'), 2),
            'paying_salons' => $payers,
            'per_paying_salon' => $payers > 0 ? round($total / $payers, 2) : 0,
        ];
    }

    /** Commission calculated in payouts not yet settled, net of coins already put against it. */
    private function pendingCommission(): array
    {
        $row = DB::table('salon_payouts')
            ->whereIn('status', [PayoutService::STATUS_PENDING, PayoutService::STATUS_APPROVED])
            ->where('commission_deducted', '>', 0)
            ->selectRaw('count(*) as payouts, coalesce(sum(commission_deducted), 0) as commission, coalesce(sum(wallet_redeemed_amount), 0) as coins')
            ->first();

        return [
            'amount' => round(max(0, (float) $row->commission - (float) $row->coins), 2),
            'payouts' => (int) $row->payouts,
        ];
    }

    /** Every bucket in the window, empty ones included, so the chart has no gaps. */
    private function trend(Collection $entries, Carbon $from, Carbon $to, string $granularity): array
    {
        $keyOf = fn (Carbon $d) => match ($granularity) {
            'weekly' => $d->copy()->startOfWeek()->toDateString(),
            'monthly' => $d->format('Y-m-01'),
            default => $d->toDateString(),
        };

        $sums = [];
        foreach ($entries as $e) {
            $k = $keyOf($e['at']);
            $sums[$k][$e['kind']] = ($sums[$k][$e['kind']] ?? 0) + $e['amount'];
            $sums[$k]['coins'] = ($sums[$k]['coins'] ?? 0) + $e['coins'];
        }

        $cursor = match ($granularity) {
            'weekly' => $from->copy()->startOfWeek(),
            'monthly' => $from->copy()->startOfMonth(),
            default => $from->copy()->startOfDay(),
        };

        $out = [];
        while ($cursor->lte($to)) {
            $k = $keyOf($cursor);
            $subs = round($sums[$k]['subscription'] ?? 0, 2);
            $comm = round($sums[$k]['commission'] ?? 0, 2);
            $out[] = [
                'date' => $k,
                'label' => match ($granularity) {
                    'weekly' => $cursor->format('d M') . ' – ' . $cursor->copy()->addDays(6)->format('d M'),
                    'monthly' => $cursor->format('M Y'),
                    default => $cursor->format('d M'),
                },
                'subscriptions' => $subs,
                'commission' => $comm,
                'total' => round($subs + $comm, 2),
                'coins' => round($sums[$k]['coins'] ?? 0, 2),
            ];
            $cursor = match ($granularity) {
                'weekly' => $cursor->addWeek(),
                'monthly' => $cursor->addMonth(),
                default => $cursor->addDay(),
            };
        }

        return $out;
    }

    /** Plan payments by plan, with commission as its own slice. */
    private function byPlan(Collection $entries): array
    {
        $slices = $entries->where('kind', 'subscription')
            ->groupBy('label')
            ->map(fn ($g, $label) => ['name' => $label, 'amount' => round($g->sum('amount'), 2), 'count' => $g->count()])
            ->values();

        $commission = $entries->where('kind', 'commission');
        if ($commission->isNotEmpty()) {
            $slices->push(['name' => 'Commission', 'amount' => round($commission->sum('amount'), 2), 'count' => $commission->count()]);
        }

        return $slices->sortByDesc('amount')->values()->all();
    }

    private function group(Collection $entries, string $field, int $limit, bool $withId = false): array
    {
        return $entries->groupBy($withId ? 'salon_id' : $field)
            ->map(function ($g) use ($field, $withId) {
                $row = [
                    'name' => $g->first()[$field],
                    'subscriptions' => round($g->where('kind', 'subscription')->sum('amount'), 2),
                    'commission' => round($g->where('kind', 'commission')->sum('amount'), 2),
                    'total' => round($g->sum('amount'), 2),
                ];
                if ($withId) {
                    $row = ['id' => $g->first()['salon_id'], 'city' => $g->first()['city']] + $row;
                }

                return $row;
            })
            ->sortByDesc('total')
            ->take($limit)
            ->values()
            ->all();
    }

    /**
     * Month-by-month ledger: what BookALook earned each month, and from which
     * salon, plus money still on its way (open commission, plan renewals due).
     */
    public function monthly(Request $request)
    {
        $request->validate(['months' => 'nullable|integer|in:3,6,12,24']);
        $count = (int) $request->input('months', 12);

        $now = Carbon::now();
        $end = $now->copy()->endOfMonth();
        $start = $now->copy()->startOfMonth()->subMonthsNoOverflow($count - 1);

        $all = $this->entries(null, null);
        // When each salon first paid BookALook, for "new paying salons".
        $firstPaid = $all->where('amount', '>', 0)->groupBy('salon_id')
            ->map(fn ($g) => $g->min('at')->format('Y-m'));

        $entries = $all->filter(fn ($e) => $e['at']->between($start, $end))->values();
        $byMonth = $entries->groupBy(fn ($e) => $e['at']->format('Y-m'));

        $months = [];
        $cursor = $start->copy();
        $prevTotal = null;
        while ($cursor->lte($end)) {
            $key = $cursor->format('Y-m');
            $g = $byMonth->get($key, collect());
            $total = round($g->sum('amount'), 2);
            $payers = $g->where('amount', '>', 0)->pluck('salon_id')->unique();
            $months[] = [
                'key' => $key,
                'label' => $cursor->format('M Y'),
                'subscriptions' => round($g->where('kind', 'subscription')->sum('amount'), 2),
                'commission' => round($g->where('kind', 'commission')->sum('amount'), 2),
                'total' => $total,
                'coins' => round($g->sum('coins'), 2),
                'payments' => $g->count(),
                'paying_salons' => $payers->count(),
                'new_paying_salons' => $payers->filter(fn ($id) => ($firstPaid[$id] ?? null) === $key)->count(),
                'growth_pct' => $prevTotal ? round((($total - $prevTotal) / $prevTotal) * 100, 1) : null,
                'is_current' => $key === $now->format('Y-m'),
            ];
            $prevTotal = $total;
            $cursor->addMonthNoOverflow();
        }

        $current = $this->currentBilling();

        $salons = $entries->groupBy('salon_id')->map(function ($g, $id) use ($current, $firstPaid) {
            $first = $g->first();

            return [
                'id' => (string) $id,
                'name' => $first['salon'],
                'city' => $first['city'],
                'billing' => $current[$id] ?? null,
                'subscriptions' => round($g->where('kind', 'subscription')->sum('amount'), 2),
                'commission' => round($g->where('kind', 'commission')->sum('amount'), 2),
                'total' => round($g->sum('amount'), 2),
                'coins' => round($g->sum('coins'), 2),
                'payments' => $g->count(),
                'active_months' => $g->map(fn ($e) => $e['at']->format('Y-m'))->unique()->count(),
                'first_paid' => $firstPaid[$id] ?? null,
                'months' => $g->groupBy(fn ($e) => $e['at']->format('Y-m'))->map(fn ($m) => [
                    'subscriptions' => round($m->where('kind', 'subscription')->sum('amount'), 2),
                    'commission' => round($m->where('kind', 'commission')->sum('amount'), 2),
                    'total' => round($m->sum('amount'), 2),
                    'coins' => round($m->sum('coins'), 2),
                    'items' => $m->sortBy('at')->values()->map(fn ($e) => [
                        'kind' => $e['kind'],
                        'label' => $e['label'],
                        'amount' => $e['amount'],
                        'coins' => $e['coins'],
                        'at' => $e['at']->toIso8601String(),
                    ])->all(),
                ])->all(),
            ];
        })->sortByDesc('total')->values()->all();

        return response()->json([
            'success' => true,
            'range' => ['from' => $start->toDateString(), 'to' => $end->toDateString(), 'months' => $count],
            'months' => $months,
            'salons' => $salons,
            'insights' => $this->insights($all, $months, $now),
            'pending_by_salon' => $this->pendingBySalon(),
            'upcoming_renewals' => $this->upcomingRenewals($now),
        ]);
    }

    /** The billing each salon is on today: its live plan, or Commission Model. */
    private function currentBilling(): array
    {
        return DB::table('salon_subscriptions as ss')
            ->leftJoin('subscription_plans as p', 'p.id', '=', 'ss.plan_id')
            ->where('ss.status', 'active')
            ->whereDate('ss.end_date', '>=', Carbon::today()->toDateString())
            ->orderBy('ss.end_date')
            ->get(['ss.salon_id', 'ss.billing_type', 'p.name as plan'])
            ->mapWithKeys(fn ($r) => [(string) $r->salon_id => $r->billing_type === 'commission' ? 'Commission Model' : ($r->plan ?? 'Plan')])
            ->all();
    }

    private function insights(Collection $all, array $months, Carbon $now): array
    {
        $full = array_values(array_filter($months, fn ($m) => ! $m['is_current']));
        $best = collect($months)->sortByDesc('total')->first();
        $lastThree = array_slice($full, -3);

        // This month so far against last month up to the same day.
        $lastStart = $now->copy()->subMonthNoOverflow()->startOfMonth();
        $lastSamePoint = $lastStart->copy()->addDays(min($now->day, $lastStart->daysInMonth) - 1)->setTimeFrom($now);
        $mtd = round($all->filter(fn ($e) => $e['at']->between($now->copy()->startOfMonth(), $now))->sum('amount'), 2);
        $lastMtd = round($all->filter(fn ($e) => $e['at']->between($lastStart, $lastSamePoint))->sum('amount'), 2);

        // Salons who paid in at least two of the months shown.
        $keys = array_column($months, 'key');
        $perSalon = $all->filter(fn ($e) => $e['amount'] > 0 && in_array($e['at']->format('Y-m'), $keys, true))
            ->groupBy('salon_id')
            ->map(fn ($g) => $g->map(fn ($e) => $e['at']->format('Y-m'))->unique()->count());

        $cash = array_sum(array_column($months, 'total'));
        $coins = array_sum(array_column($months, 'coins'));

        return [
            'month_to_date' => $mtd,
            'last_month_same_point' => $lastMtd,
            'average_month' => count($full) ? round(array_sum(array_column($full, 'total')) / count($full), 2) : 0,
            'best_month' => $best && $best['total'] > 0 ? ['label' => $best['label'], 'total' => $best['total']] : null,
            'annual_run_rate' => count($lastThree) ? round(array_sum(array_column($lastThree, 'total')) / count($lastThree) * 12, 2) : 0,
            'paying_salons' => $perSalon->count(),
            'repeat_salons' => $perSalon->filter(fn ($n) => $n >= 2)->count(),
            'coins_share_pct' => $cash + $coins > 0 ? round($coins / ($cash + $coins) * 100, 1) : 0,
        ];
    }

    /** Open commission, salon by salon: earned by BookALook, not yet settled. */
    private function pendingBySalon(): array
    {
        return DB::table('salon_payouts as sp')
            ->join('salons as s', 's.id', '=', 'sp.salon_id')
            ->leftJoin('cities as c', 'c.id', '=', 's.city_id')
            ->whereIn('sp.status', [PayoutService::STATUS_PENDING, PayoutService::STATUS_APPROVED])
            ->where('sp.commission_deducted', '>', 0)
            ->groupBy('sp.salon_id', 's.name', 'c.name')
            ->selectRaw('sp.salon_id, s.name, c.name as city, count(*) as payouts, sum(sp.commission_deducted) as commission, coalesce(sum(sp.wallet_redeemed_amount), 0) as coins, min(sp.cycle_start_date) as oldest')
            ->get()
            ->map(fn ($r) => [
                'id' => (string) $r->salon_id,
                'name' => $r->name,
                'city' => $r->city ?? 'No city',
                'amount' => round(max(0, (float) $r->commission - (float) $r->coins), 2),
                'payouts' => (int) $r->payouts,
                'oldest_cycle' => $r->oldest ? Carbon::parse($r->oldest)->toDateString() : null,
            ])
            ->filter(fn ($r) => $r['amount'] > 0)
            ->sortByDesc('amount')
            ->values()
            ->all();
    }

    /** Plan subscriptions ending in the next 30 days: renewal money to expect. */
    private function upcomingRenewals(Carbon $now): array
    {
        $rows = DB::table('salon_subscriptions as ss')
            ->join('salons as s', 's.id', '=', 'ss.salon_id')
            ->leftJoin('subscription_plans as p', 'p.id', '=', 'ss.plan_id')
            ->where('ss.status', 'active')
            ->where('ss.billing_type', '!=', 'commission')
            ->whereDate('ss.end_date', '>=', $now->toDateString())
            ->whereDate('ss.end_date', '<=', $now->copy()->addDays(30)->toDateString())
            ->orderBy('ss.end_date')
            ->get(['ss.salon_id', 's.name', 'p.name as plan', 'p.price', 'ss.plan_price_snapshot', 'ss.end_date', 'ss.auto_renew'])
            ->map(fn ($r) => [
                'id' => (string) $r->salon_id,
                'name' => $r->name,
                'plan' => $r->plan ?? 'Plan',
                'price' => round((float) ($r->price ?? $r->plan_price_snapshot ?? 0), 2),
                'end_date' => Carbon::parse($r->end_date)->toDateString(),
                'auto_renew' => (bool) $r->auto_renew,
            ]);

        return [
            'amount' => round($rows->sum('price'), 2),
            'count' => $rows->count(),
            'items' => $rows->take(12)->values()->all(),
        ];
    }
}
