<?php

namespace App\Services\Marketing;

use App\Models\Salon;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * What a salon's own bookings say about it.
 *
 * Everything here is derived from completed appointments. Nothing is stored,
 * nothing is precomputed and no nightly job keeps a table in step — the numbers
 * are small (a busy salon books a few thousand times a year) and a figure
 * calculated on the spot cannot drift away from the bookings it describes.
 *
 * The split between basic and advanced is the plan spec's, not a technical one:
 * the same queries run either way, and the controller decides how much of the
 * answer a plan is entitled to see.
 */
class SalonInsightsService
{
    /** Bookings older than this stop describing how the salon works today. */
    private const WINDOW_DAYS = 180;

    public function __construct(private MarketingSettings $settings)
    {
    }

    /**
     * Headline numbers: how many customers, how many came back, what they spend.
     */
    public function overview(Salon $salon, int $days = self::WINDOW_DAYS): array
    {
        $since = now()->subDays($days)->toDateString();

        $rows = $this->customerRows($salon, $since);

        $returning = $rows->filter(fn ($row) => $row->visits > 1);
        $revenue = $rows->sum(fn ($row) => (float) $row->spend);
        $visits = $rows->sum(fn ($row) => (int) $row->visits);

        return [
            'window_days' => $days,
            'customers' => $rows->count(),
            'returning_customers' => $returning->count(),
            // The one number that says whether the salon is building something
            // or just processing strangers.
            'repeat_rate' => $rows->count() > 0
                ? round($returning->count() / $rows->count() * 100, 1)
                : 0.0,
            'total_visits' => $visits,
            'revenue' => round($revenue, 2),
            'average_bill' => $visits > 0 ? round($revenue / $visits, 2) : 0.0,
            'average_visits_per_customer' => $rows->count() > 0
                ? round($visits / $rows->count(), 1)
                : 0.0,
        ];
    }

    /**
     * Real 30-day revenue trend broken down into 4 weekly periods.
     */
    public function revenueTrend(Salon $salon, int $days = 30): array
    {
        $since = now()->subDays($days)->toDateString();

        $totalStats = DB::table('appointments')
            ->where('salon_id', $salon->id)
            ->where('status', 'completed')
            ->whereDate('appointment_date', '>=', $since)
            ->selectRaw('COUNT(*) as bookings, COALESCE(SUM(COALESCE(final_billed_amount, total_amount)), 0) as revenue')
            ->first();

        // 4 weekly buckets covering the last ~28-30 days
        $intervals = [
            [
                'label' => 'W1',
                'start' => now()->subDays(28)->toDateString(),
                'end' => now()->subDays(22)->toDateString(),
                'period' => now()->subDays(28)->format('d M') . ' - ' . now()->subDays(22)->format('d M'),
            ],
            [
                'label' => 'W2',
                'start' => now()->subDays(21)->toDateString(),
                'end' => now()->subDays(15)->toDateString(),
                'period' => now()->subDays(21)->format('d M') . ' - ' . now()->subDays(15)->format('d M'),
            ],
            [
                'label' => 'W3',
                'start' => now()->subDays(14)->toDateString(),
                'end' => now()->subDays(8)->toDateString(),
                'period' => now()->subDays(14)->format('d M') . ' - ' . now()->subDays(8)->format('d M'),
            ],
            [
                'label' => 'W4',
                'start' => now()->subDays(7)->toDateString(),
                'end' => now()->toDateString(),
                'period' => now()->subDays(7)->format('d M') . ' - ' . now()->format('d M'),
            ],
        ];

        $weeks = [];
        foreach ($intervals as $interval) {
            $stats = DB::table('appointments')
                ->where('salon_id', $salon->id)
                ->where('status', 'completed')
                ->whereDate('appointment_date', '>=', $interval['start'])
                ->whereDate('appointment_date', '<=', $interval['end'])
                ->selectRaw('COUNT(*) as bookings, COALESCE(SUM(COALESCE(final_billed_amount, total_amount)), 0) as revenue')
                ->first();

            $weeks[] = [
                'label' => $interval['label'],
                'period' => $interval['period'],
                'revenue' => round((float) ($stats->revenue ?? 0), 2),
                'bookings' => (int) ($stats->bookings ?? 0),
            ];
        }

        return [
            'total_revenue' => round((float) ($totalStats->revenue ?? 0), 2),
            'total_bookings' => (int) ($totalStats->bookings ?? 0),
            'weeks' => $weeks,
        ];
    }

    /**
     * Real staff performance measured by completed bookings and revenue over the last 30 days.
     */
    public function staffPerformance(Salon $salon, int $days = 30): array
    {
        $since = now()->subDays($days)->toDateString();

        $providers = DB::table('service_providers as sp')
            ->join('users as u', 'u.id', '=', 'sp.user_id')
            ->where('sp.salon_id', $salon->id)
            ->whereNull('sp.deleted_at')
            ->select('sp.id', 'u.name')
            ->get();

        $staff = [];
        foreach ($providers as $p) {
            $stats = DB::table('appointments as a')
                ->where('a.salon_id', $salon->id)
                ->where('a.status', 'completed')
                ->whereDate('a.appointment_date', '>=', $since)
                ->where(function ($q) use ($p) {
                    $q->where('a.serving_provider_id', $p->id)
                      ->orWhere(function ($sub) use ($p) {
                          $sub->whereNull('a.serving_provider_id')
                              ->where('a.appointed_provider_id', $p->id);
                      });
                })
                ->selectRaw('COUNT(*) as bookings, COALESCE(SUM(COALESCE(a.final_billed_amount, a.total_amount)), 0) as revenue')
                ->first();

            $staff[] = [
                'id' => (string) $p->id,
                'name' => $p->name ?? 'Staff',
                'bookings' => (int) ($stats->bookings ?? 0),
                'revenue' => round((float) ($stats->revenue ?? 0), 2),
            ];
        }

        usort($staff, function ($a, $b) {
            if ($b['revenue'] != $a['revenue']) {
                return $b['revenue'] <=> $a['revenue'];
            }
            return $b['bookings'] <=> $a['bookings'];
        });

        return $staff;
    }

    /**
     * Real retention funnel calculated from customer visit history.
     */
    public function retentionFunnel(Salon $salon, int $days = self::WINDOW_DAYS): array
    {
        $rows = $this->customerRows($salon, now()->subDays($days)->toDateString());
        $total = $rows->count();

        $v1 = $total;
        $v2 = $rows->filter(fn ($r) => (int) $r->visits >= 2)->count();
        $v3 = $rows->filter(fn ($r) => (int) $r->visits >= 3)->count();
        $v4 = $rows->filter(fn ($r) => (int) $r->visits >= 4)->count();

        $rate1 = $total > 0 ? 100.0 : 0.0;
        $rate2 = $total > 0 ? round($v2 / $total * 100, 1) : 0.0;
        $rate3 = $total > 0 ? round($v3 / $total * 100, 1) : 0.0;
        $rate4 = $total > 0 ? round($v4 / $total * 100, 1) : 0.0;

        if ($total === 0) {
            $benchmarkMessage = 'No customer visits recorded yet. As appointments are completed, return visit rates will appear here.';
            $benchmarkIsGood = false;
        } elseif ($rate2 >= 35.0) {
            $benchmarkMessage = "Your {$rate2}% 2nd-visit rate is above the 35% industry average.";
            $benchmarkIsGood = true;
        } else {
            $benchmarkMessage = "Your {$rate2}% 2nd-visit rate is below the 35% industry average. Sending a quick follow-up offer can turn first-timers into regulars.";
            $benchmarkIsGood = false;
        }

        return [
            'total_customers' => $total,
            'first_visits' => ['count' => $v1, 'rate' => $rate1],
            'second_visits' => ['count' => $v2, 'rate' => $rate2],
            'third_visits' => ['count' => $v3, 'rate' => $rate3],
            'regular_visits' => ['count' => $v4, 'rate' => $rate4],
            'benchmark_message' => $benchmarkMessage,
            'benchmark_is_good' => $benchmarkIsGood,
        ];
    }

    /**
     * How the customer base splits by loyalty, and who is slipping away.
     *
     * "At risk" is the segment that pays for itself: customers who came often
     * enough to be regulars and then stopped, which is exactly the audience a
     * reactivation campaign exists for.
     */
    public function repeatCustomers(Salon $salon): array
    {
        $rows = $this->customerRows($salon, now()->subDays(self::WINDOW_DAYS)->toDateString());
        $inactiveAfter = $this->settings->inactiveDays();
        $repeatAt = $this->settings->repeatVisits();

        $buckets = ['once' => 0, 'occasional' => 0, 'regular' => 0];
        $atRisk = 0;

        foreach ($rows as $row) {
            $visits = (int) $row->visits;

            if ($visits === 1) {
                $buckets['once']++;
            } elseif ($visits < $repeatAt) {
                $buckets['occasional']++;
            } else {
                $buckets['regular']++;
            }

            $lapsed = $row->last_visit
                && Carbon::parse($row->last_visit)->lt(now()->subDays($inactiveAfter));

            if ($visits >= 2 && $lapsed) {
                $atRisk++;
            }
        }

        return [
            'buckets' => [
                ['label' => 'Came once', 'count' => $buckets['once']],
                ['label' => 'Occasional', 'count' => $buckets['occasional']],
                ['label' => "Regulars ({$repeatAt}+ visits)", 'count' => $buckets['regular']],
            ],
            'at_risk' => $atRisk,
            'at_risk_after_days' => $inactiveAfter,
            'top_customers' => $rows->sortByDesc(fn ($row) => (float) $row->spend)
                ->take(10)
                ->map(fn ($row) => [
                    'name' => $row->name ?: 'Walk-in customer',
                    'visits' => (int) $row->visits,
                    'spend' => round((float) $row->spend, 2),
                    'last_visit' => $row->last_visit,
                ])->values(),
        ];
    }

    /**
     * When the salon is busy — by hour, and by day of the week.
     *
     * Both are returned as complete series including the empty slots, because
     * the quiet hours are the actionable part: an offer is worth sending for a
     * Tuesday afternoon, not for the Saturday that fills itself.
     */
    public function peakHours(Salon $salon): array
    {
        $since = now()->subDays(self::WINDOW_DAYS)->toDateString();

        // start_time is stored as HH:MM:SS, so the hour is the first two
        // characters on every database this runs on.
        $byHour = DB::table('appointments')
            ->where('salon_id', $salon->id)
            ->where('status', 'completed')
            ->whereDate('appointment_date', '>=', $since)
            ->selectRaw('SUBSTR(CAST(start_time AS VARCHAR), 1, 2) as hour, COUNT(*) as bookings')
            ->groupByRaw('SUBSTR(CAST(start_time AS VARCHAR), 1, 2)')
            ->pluck('bookings', 'hour');

        $hours = [];
        for ($hour = 0; $hour < 24; $hour++) {
            $key = str_pad((string) $hour, 2, '0', STR_PAD_LEFT);
            $count = (int) ($byHour[$key] ?? 0);

            // Only the hours the salon actually trades in; a 24-row chart of
            // mostly zeroes hides the shape it is meant to show.
            if ($count > 0 || ($hour >= 8 && $hour <= 21)) {
                $hours[] = ['hour' => $hour, 'label' => $this->hourLabel($hour), 'bookings' => $count];
            }
        }

        $dates = DB::table('appointments')
            ->where('salon_id', $salon->id)
            ->where('status', 'completed')
            ->whereDate('appointment_date', '>=', $since)
            ->pluck('appointment_date');

        $byDay = array_fill(0, 7, 0);
        foreach ($dates as $date) {
            $byDay[(int) Carbon::parse($date)->dayOfWeek]++;
        }

        $dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
        $days = [];
        foreach ($byDay as $index => $count) {
            $days[] = ['day' => $dayNames[$index], 'bookings' => $count];
        }

        $busiest = collect($hours)->sortByDesc('bookings')->first();
        $quietest = collect($hours)->filter(fn ($h) => $h['bookings'] > 0)->sortBy('bookings')->first();

        return [
            'by_hour' => $hours,
            'by_day' => $days,
            'busiest_hour' => $busiest['label'] ?? null,
            'quietest_hour' => $quietest['label'] ?? null,
            // Among days the salon actually trades. A day with no bookings at
            // all is almost always a closing day, not a slow one, and calling
            // it "quietest" leads straight to advising an offer for a day the
            // shop is shut. The quietest hour above already works this way.
            'quietest_day' => collect($days)->filter(fn ($day) => $day['bookings'] > 0)
                ->sortBy('bookings')->first()['day'] ?? null,
            'closed_days' => collect($days)->filter(fn ($day) => $day['bookings'] === 0)
                ->pluck('day')->values(),
        ];
    }

    /** Where the customers come from, by saved locality. */
    public function areas(Salon $salon): array
    {
        $rows = DB::table('appointments as a')
            ->join('users as u', 'u.id', '=', 'a.customer_id')
            ->leftJoin('sub_areas as sa', 'sa.id', '=', 'u.sub_area_id')
            ->where('a.salon_id', $salon->id)
            ->where('a.status', 'completed')
            ->whereNotNull('u.sub_area_id')
            ->selectRaw('sa.id as sub_area_id, sa.name as area, COUNT(DISTINCT u.id) as customers, COUNT(*) as visits')
            ->groupBy('sa.id', 'sa.name')
            ->orderByDesc('customers')
            ->limit(12)
            ->get();

        return [
            'areas' => $rows->map(fn ($row) => [
                'sub_area_id' => $row->sub_area_id,
                'area' => $row->area ?? 'Not set',
                'customers' => (int) $row->customers,
                'visits' => (int) $row->visits,
            ])->values(),
            // Walk-ins and customers who never set an area are invisible here,
            // and saying so is better than letting the total look wrong.
            'note' => 'Only customers with an account and a saved area appear here.',
        ];
    }

    /** Which services earn, and which merely happen. */
    public function services(Salon $salon, int $limit = 10): array
    {
        $rows = DB::table('appointment_services as asv')
            ->join('appointments as a', 'a.id', '=', 'asv.appointment_id')
            ->join('services as s', 's.id', '=', 'asv.service_id')
            ->leftJoin('service_templates as t', 't.id', '=', 's.template_id')
            ->where('a.salon_id', $salon->id)
            ->where('a.status', 'completed')
            ->selectRaw('s.id as service_id, COALESCE(t.name, \'Custom service\') as name, COUNT(*) as bookings, SUM(asv.price_at_booking) as revenue')
            ->groupBy('s.id', 't.name')
            ->orderByDesc('bookings')
            ->limit($limit)
            ->get();

        return $rows->map(fn ($row) => [
            'service_id' => $row->service_id,
            'name' => $row->name,
            'bookings' => (int) $row->bookings,
            'revenue' => round((float) $row->revenue, 2),
        ])->values()->all();
    }

    /**
     * Services customers already buy together.
     *
     * Cross-sell, evidenced rather than guessed: a pair that keeps appearing on
     * the same bill is a pair worth suggesting, and worth turning into a combo.
     * The self-join is ordered so each pair is counted once rather than twice.
     */
    public function pairs(Salon $salon, int $limit = 8): array
    {
        $rows = DB::table('appointment_services as a1')
            ->join('appointment_services as a2', function ($join) {
                $join->on('a1.appointment_id', '=', 'a2.appointment_id')
                    ->whereColumn('a1.service_id', '<', 'a2.service_id');
            })
            ->join('appointments as ap', 'ap.id', '=', 'a1.appointment_id')
            ->join('services as s1', 's1.id', '=', 'a1.service_id')
            ->join('services as s2', 's2.id', '=', 'a2.service_id')
            ->leftJoin('service_templates as t1', 't1.id', '=', 's1.template_id')
            ->leftJoin('service_templates as t2', 't2.id', '=', 's2.template_id')
            ->where('ap.salon_id', $salon->id)
            ->where('ap.status', 'completed')
            ->selectRaw(
                'a1.service_id as first_id, a2.service_id as second_id, '
                .'COALESCE(t1.name, \'Custom\') as first_name, COALESCE(t2.name, \'Custom\') as second_name, '
                .'COUNT(*) as together, SUM(a1.price_at_booking + a2.price_at_booking) as revenue'
            )
            ->groupBy('a1.service_id', 'a2.service_id', 't1.name', 't2.name')
            ->havingRaw('COUNT(*) > 1')
            ->orderByDesc('together')
            ->limit($limit)
            ->get();

        // Pairs already sold as a combo are not a recommendation; they are the
        // salon's existing idea reflected back at it.
        $existing = DB::table('combo_services as cs1')
            ->join('combo_services as cs2', function ($join) {
                $join->on('cs1.combo_id', '=', 'cs2.combo_id')
                    ->whereColumn('cs1.service_id', '<', 'cs2.service_id');
            })
            ->join('combos as c', 'c.id', '=', 'cs1.combo_id')
            ->where('c.salon_id', $salon->id)
            ->selectRaw('cs1.service_id as a, cs2.service_id as b')
            ->get()
            ->map(fn ($row) => $row->a.'|'.$row->b)
            ->flip();

        return $rows->map(fn ($row) => [
            'services' => [$row->first_name, $row->second_name],
            'service_ids' => [$row->first_id, $row->second_id],
            'booked_together' => (int) $row->together,
            'revenue' => round((float) $row->revenue, 2),
            'already_a_combo' => $existing->has($row->first_id.'|'.$row->second_id),
        ])->values()->all();
    }

    /**
     * Combos worth creating.
     *
     * The pairs customers already choose for themselves, minus the ones the
     * salon has already packaged. Turning one into a combo is the plan spec's
     * higher-bill mechanism, and this is the evidence for which to build.
     */
    public function recommendedCombos(Salon $salon): array
    {
        return collect($this->pairs($salon, 20))
            ->reject(fn (array $pair) => $pair['already_a_combo'])
            ->take(5)
            ->map(fn (array $pair) => [
                'services' => $pair['services'],
                'service_ids' => $pair['service_ids'],
                'booked_together' => $pair['booked_together'],
                'suggestion' => sprintf(
                    '%s customers booked %s and %s on the same visit. A combo would make that the obvious choice.',
                    $pair['booked_together'],
                    $pair['services'][0],
                    $pair['services'][1],
                ),
            ])->values()->all();
    }

    /**
     * Upsell: a dearer service the salon already sells, against a popular
     * cheaper one.
     *
     * Only suggested where customers have actually bought both, so it is a
     * trade-up somebody has made before rather than an arbitrary price ladder.
     */
    public function upsell(Salon $salon): array
    {
        $prices = DB::table('services as s')
            ->leftJoin('service_templates as t', 't.id', '=', 's.template_id')
            ->where('s.salon_id', $salon->id)
            ->whereNull('s.deleted_at')
            ->selectRaw('s.id, COALESCE(t.name, \'Custom service\') as name, s.price')
            ->get()
            ->keyBy('id');

        $suggestions = [];

        foreach ($this->pairs($salon, 20) as $pair) {
            [$firstId, $secondId] = $pair['service_ids'];
            $first = $prices[$firstId] ?? null;
            $second = $prices[$secondId] ?? null;

            if (! $first || ! $second) {
                continue;
            }

            $cheaper = (float) $first->price <= (float) $second->price ? $first : $second;
            $dearer = $cheaper === $first ? $second : $first;

            // A few rupees apart is not an upsell.
            if ((float) $dearer->price < (float) $cheaper->price * 1.3) {
                continue;
            }

            $suggestions[] = [
                'from' => $cheaper->name,
                'to' => $dearer->name,
                'uplift' => round((float) $dearer->price - (float) $cheaper->price, 2),
                'evidence' => $pair['booked_together'],
            ];

            if (count($suggestions) >= 5) {
                break;
            }
        }

        return $suggestions;
    }

    /**
     * How the salon's marketing has actually performed.
     *
     * Read rate is measured against delivered rather than sent, because a
     * message that never arrived says nothing about whether the offer was any
     * good.
     */
    public function campaignPerformance(Salon $salon, int $days = 90): ?array
    {
        // Insights and marketing are separate features that happen to share a
        // screen. Where marketing has not been deployed the booking insights
        // are still perfectly computable, and losing the whole page to a table
        // that does not exist yet is a far worse answer than omitting one card.
        if (! Schema::hasTable('campaigns')) {
            return null;
        }

        $since = now()->subDays($days);

        $campaigns = DB::table('campaigns')
            ->leftJoin('campaign_templates as t', 't.id', '=', 'campaigns.campaign_template_id')
            ->where('campaigns.salon_id', $salon->id)
            ->where('campaigns.created_at', '>=', $since)
            ->whereIn('campaigns.status', ['sent', 'sending'])
            ->selectRaw(
                't.category, COUNT(*) as campaigns, '
                .'SUM(campaigns.sent_count) as sent, SUM(campaigns.delivered_count) as delivered, '
                .'SUM(campaigns.read_count) as read_total, SUM(campaigns.failed_count) as failed'
            )
            ->groupBy('t.category')
            ->get();

        $sent = (int) $campaigns->sum('sent');
        $delivered = (int) $campaigns->sum('delivered');
        $read = (int) $campaigns->sum('read_total');

        return [
            'window_days' => $days,
            'campaigns' => (int) $campaigns->sum('campaigns'),
            'sent' => $sent,
            'delivered' => $delivered,
            'read' => $read,
            'delivery_rate' => $sent > 0 ? round($delivered / $sent * 100, 1) : null,
            'read_rate' => $delivered > 0 ? round($read / $delivered * 100, 1) : null,
            'by_category' => $campaigns->map(fn ($row) => [
                'category' => $row->category ?? 'other',
                'campaigns' => (int) $row->campaigns,
                'sent' => (int) $row->sent,
                'read_rate' => (int) $row->delivered > 0
                    ? round((int) $row->read_total / (int) $row->delivered * 100, 1)
                    : null,
            ])->values(),
        ];
    }

    /**
     * This period against the one before it: revenue, visits, customers and
     * the average bill, each with how far it moved.
     */
    public function periodComparison(Salon $salon, int $days): array
    {
        $end = now()->toDateString();
        $start = now()->subDays($days - 1)->toDateString();
        $previousEnd = now()->subDays($days)->toDateString();
        $previousStart = now()->subDays($days * 2 - 1)->toDateString();

        $current = $this->periodTotals($salon, $start, $end);
        $previous = $this->periodTotals($salon, $previousStart, $previousEnd);

        $metrics = [];
        foreach (['revenue', 'visits', 'customers', 'average_bill'] as $key) {
            $metrics[$key] = [
                'current' => $current[$key],
                'previous' => $previous[$key],
                // Null rather than "+100%" when there was nothing before:
                // growth from zero is not a percentage.
                'change_percent' => $previous[$key] > 0
                    ? round(($current[$key] - $previous[$key]) / $previous[$key] * 100, 1)
                    : null,
            ];
        }

        return [
            'days' => $days,
            'from' => $start,
            'to' => $end,
            'previous_from' => $previousStart,
            'previous_to' => $previousEnd,
            'metrics' => $metrics,
        ];
    }

    /** @return array{revenue: float, visits: int, customers: int, average_bill: float} */
    private function periodTotals(Salon $salon, string $from, string $to): array
    {
        $row = DB::table('appointments as a')
            ->leftJoin('users as u', 'u.id', '=', 'a.customer_id')
            ->where('a.salon_id', $salon->id)
            ->where('a.status', 'completed')
            ->whereDate('a.appointment_date', '>=', $from)
            ->whereDate('a.appointment_date', '<=', $to)
            ->selectRaw(
                'COUNT(*) as visits, '
                .'COALESCE(SUM(COALESCE(a.final_billed_amount, a.total_amount)), 0) as revenue, '
                .'COUNT(DISTINCT COALESCE(u.phone, a.walk_in_customer_phone, a.walk_in_customer_name, CAST(a.id AS VARCHAR))) as customers'
            )
            ->first();

        $visits = (int) ($row->visits ?? 0);
        $revenue = round((float) ($row->revenue ?? 0), 2);

        return [
            'revenue' => $revenue,
            'visits' => $visits,
            'customers' => (int) ($row->customers ?? 0),
            'average_bill' => $visits > 0 ? round($revenue / $visits, 2) : 0.0,
        ];
    }

    /**
     * Who each service is booked for: men, women, or not recorded.
     *
     * The person in the chair, not the account holder — a booking made for
     * someone else counts under the recipient's gender.
     */
    public function genderMix(Salon $salon, int $limit = 10): array
    {
        $gender = "LOWER(COALESCE(a.recipient_gender, a.walk_in_customer_gender, u.gender, 'unspecified'))";

        $rows = DB::table('appointment_services as asv')
            ->join('appointments as a', 'a.id', '=', 'asv.appointment_id')
            ->leftJoin('users as u', 'u.id', '=', 'a.customer_id')
            ->join('services as s', 's.id', '=', 'asv.service_id')
            ->leftJoin('service_templates as t', 't.id', '=', 's.template_id')
            ->where('a.salon_id', $salon->id)
            ->where('a.status', 'completed')
            ->whereDate('a.appointment_date', '>=', now()->subDays(self::WINDOW_DAYS)->toDateString())
            ->selectRaw("s.id as service_id, COALESCE(t.name, 'Custom service') as name, {$gender} as gender, COUNT(*) as bookings")
            ->groupBy('s.id', 't.name', DB::raw($gender))
            ->get();

        $bucketOf = fn (?string $gender) => match ($gender) {
            'male', 'men' => 'male',
            'female', 'women' => 'female',
            default => 'unknown',
        };

        $services = [];
        foreach ($rows as $row) {
            $bucket = $bucketOf($row->gender);
            $services[$row->service_id] ??= ['service_id' => $row->service_id, 'name' => $row->name, 'male' => 0, 'female' => 0, 'unknown' => 0, 'total' => 0];
            $services[$row->service_id][$bucket] += (int) $row->bookings;
            $services[$row->service_id]['total'] += (int) $row->bookings;
        }

        // The overall split counts visits, not service lines, so a customer
        // who had three services is still one person in the chair.
        $totals = ['male' => 0, 'female' => 0, 'unknown' => 0];
        DB::table('appointments as a')
            ->leftJoin('users as u', 'u.id', '=', 'a.customer_id')
            ->where('a.salon_id', $salon->id)
            ->where('a.status', 'completed')
            ->whereDate('a.appointment_date', '>=', now()->subDays(self::WINDOW_DAYS)->toDateString())
            ->selectRaw("{$gender} as gender, COUNT(*) as visits")
            ->groupBy(DB::raw($gender))
            ->get()
            ->each(function ($row) use (&$totals, $bucketOf) {
                $totals[$bucketOf($row->gender)] += (int) $row->visits;
            });

        return [
            'overall' => $totals,
            'services' => collect($services)->sortByDesc('total')->take($limit)->values()->all(),
        ];
    }

    /**
     * How much a visit is worth and how long customers leave between visits.
     *
     * The gap is measured only over customers who came back at least once; a
     * one-off visitor has no gap, and counting them as "never" would make
     * every salon look like nobody returns.
     */
    public function visitGap(Salon $salon): array
    {
        $since = now()->subDays(self::WINDOW_DAYS)->toDateString();

        $visits = DB::table('appointments as a')
            ->leftJoin('users as u', 'u.id', '=', 'a.customer_id')
            ->where('a.salon_id', $salon->id)
            ->where('a.status', 'completed')
            ->whereDate('a.appointment_date', '>=', $since)
            ->selectRaw("COALESCE(u.phone, a.walk_in_customer_phone, a.walk_in_customer_name, CAST(a.id AS VARCHAR)) as customer, a.appointment_date, COALESCE(a.final_billed_amount, a.total_amount) as bill")
            ->orderBy('a.appointment_date')
            ->get();

        $gaps = [];
        foreach ($visits->groupBy('customer') as $customerVisits) {
            $dates = $customerVisits->pluck('appointment_date')->map(fn ($d) => Carbon::parse($d)->startOfDay())->unique()->values();
            for ($i = 1; $i < $dates->count(); $i++) {
                $gaps[] = (int) abs($dates[$i - 1]->diffInDays($dates[$i]));
            }
        }

        $bills = $visits->pluck('bill')->map(fn ($b) => (float) $b);
        sort($gaps);

        return [
            'average_bill' => $bills->count() > 0 ? round($bills->avg(), 2) : 0.0,
            'highest_bill' => $bills->count() > 0 ? round($bills->max(), 2) : 0.0,
            'average_gap_days' => count($gaps) > 0 ? (int) round(array_sum($gaps) / count($gaps)) : null,
            'median_gap_days' => count($gaps) > 0 ? (int) $gaps[intdiv(count($gaps), 2)] : null,
            'returning_visits_measured' => count($gaps),
        ];
    }

    /**
     * Each provider in more depth than the basic table: average bill, how many
     * of their customers came back to them, and how many bookings were lost to
     * no-shows.
     */
    public function staffDeepDive(Salon $salon, int $days = 90): array
    {
        $since = now()->subDays($days)->toDateString();

        $rows = DB::table('appointments as a')
            ->leftJoin('users as u', 'u.id', '=', 'a.customer_id')
            ->join('service_providers as sp', 'sp.id', '=', DB::raw('COALESCE(a.serving_provider_id, a.appointed_provider_id)'))
            ->join('users as su', 'su.id', '=', 'sp.user_id')
            ->where('a.salon_id', $salon->id)
            ->whereIn('a.status', ['completed', 'no_show'])
            ->whereDate('a.appointment_date', '>=', $since)
            ->whereNull('sp.deleted_at')
            ->selectRaw("sp.id as provider_id, su.name as provider, a.status, COALESCE(u.phone, a.walk_in_customer_phone, a.walk_in_customer_name, CAST(a.id AS VARCHAR)) as customer, COALESCE(a.final_billed_amount, a.total_amount) as bill")
            ->get();

        return $rows->groupBy('provider_id')->map(function ($bookings) {
            $done = $bookings->where('status', 'completed');
            $customers = $done->groupBy('customer');
            $returning = $customers->filter(fn ($visits) => $visits->count() > 1)->count();
            $revenue = $done->sum(fn ($b) => (float) $b->bill);

            return [
                'id' => (string) $bookings->first()->provider_id,
                'name' => $bookings->first()->provider ?? 'Staff',
                'completed' => $done->count(),
                'revenue' => round($revenue, 2),
                'average_bill' => $done->count() > 0 ? round($revenue / $done->count(), 2) : 0.0,
                'customers' => $customers->count(),
                'repeat_rate' => $customers->count() > 0 ? round($returning / $customers->count() * 100, 1) : 0.0,
                'no_shows' => $bookings->where('status', 'no_show')->count(),
            ];
        })->sortByDesc('revenue')->values()->all();
    }

    /**
     * How often each upsell the salon set up is actually taken: of the
     * completed bookings that had the main service, how many also had the
     * suggested one.
     */
    public function upsellLinkPerformance(Salon $salon): array
    {
        if (! Schema::hasTable('service_upsells')) {
            return [];
        }

        $since = now()->subDays(self::WINDOW_DAYS)->toDateString();

        $links = DB::table('service_upsells as su')
            ->join('services as s', 's.id', '=', 'su.service_id')
            ->join('services as us', 'us.id', '=', 'su.upsell_service_id')
            ->leftJoin('service_templates as t', 't.id', '=', 's.template_id')
            ->leftJoin('service_templates as ut', 'ut.id', '=', 'us.template_id')
            ->where('s.salon_id', $salon->id)
            ->whereNull('s.deleted_at')
            ->whereNull('us.deleted_at')
            ->selectRaw("su.service_id, su.upsell_service_id, COALESCE(t.name, 'Custom service') as service, COALESCE(ut.name, 'Custom service') as upsell, us.price as upsell_price")
            ->get();

        return $links->map(function ($link) use ($salon, $since) {
            $withMain = DB::table('appointment_services as asv')
                ->join('appointments as a', 'a.id', '=', 'asv.appointment_id')
                ->where('a.salon_id', $salon->id)
                ->where('a.status', 'completed')
                ->whereDate('a.appointment_date', '>=', $since)
                ->where('asv.service_id', $link->service_id)
                ->distinct()
                ->pluck('a.id');

            $taken = $withMain->isEmpty() ? 0 : DB::table('appointment_services')
                ->whereIn('appointment_id', $withMain)
                ->where('service_id', $link->upsell_service_id)
                ->distinct()
                ->count('appointment_id');

            return [
                'service' => $link->service,
                'upsell' => $link->upsell,
                'bookings' => $withMain->count(),
                'taken' => $taken,
                'take_rate' => $withMain->count() > 0 ? round($taken / $withMain->count() * 100, 1) : null,
                'extra_revenue' => round($taken * (float) $link->upsell_price, 2),
            ];
        })->sortByDesc('bookings')->values()->all();
    }

    /**
     * The emptiest day-and-hour slots the salon trades in, each with an offer
     * idea built on a service customers already like.
     */
    public function quietHourOffers(Salon $salon, int $limit = 3): array
    {
        $since = now()->subDays(self::WINDOW_DAYS)->toDateString();

        $bookings = DB::table('appointments')
            ->where('salon_id', $salon->id)
            ->where('status', 'completed')
            ->whereDate('appointment_date', '>=', $since)
            ->get(['appointment_date', 'start_time']);

        if ($bookings->count() < 10) {
            return [];
        }

        $grid = [];
        foreach ($bookings as $booking) {
            $day = (int) Carbon::parse($booking->appointment_date)->dayOfWeek;
            $hour = (int) substr((string) $booking->start_time, 0, 2);
            $grid[$day][$hour] = ($grid[$day][$hour] ?? 0) + 1;
        }

        // Only days and hours the salon is seen trading in. An hour with no
        // bookings on any day is most likely before opening or after closing.
        $tradingHours = collect($grid)->flatMap(fn ($hours) => array_keys($hours))->unique()->sort()->values();
        $busiest = collect($grid)->flatMap(fn ($hours) => array_values($hours))->max();
        $dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

        $slots = [];
        foreach (array_keys($grid) as $day) {
            foreach ($tradingHours as $hour) {
                $slots[] = ['day' => $day, 'hour' => $hour, 'bookings' => $grid[$day][$hour] ?? 0];
            }
        }

        $popular = $this->services($salon, 1)[0]['name'] ?? null;

        return collect($slots)
            ->sortBy('bookings')
            ->take($limit)
            ->map(function (array $slot) use ($dayNames, $busiest, $popular) {
                $label = $dayNames[$slot['day']].' '.$this->hourLabel($slot['hour']).'–'.$this->hourLabel(($slot['hour'] + 1) % 24);

                return [
                    'day' => $dayNames[$slot['day']],
                    'hour' => $slot['hour'],
                    'label' => $label,
                    'bookings' => $slot['bookings'],
                    'busiest_slot_bookings' => (int) $busiest,
                    'suggestion' => $popular
                        ? "{$label} is one of your emptiest hours. Try a small discount on {$popular} for this slot to fill the chairs."
                        : "{$label} is one of your emptiest hours. A slot-only offer could fill the chairs.",
                ];
            })->values()->all();
    }

    /**
     * Services losing bookings: the last 30 days against the 30 before, and
     * services nobody has booked for two months.
     */
    public function slowServices(Salon $salon): array
    {
        $counts = fn (string $from, string $to) => DB::table('appointment_services as asv')
            ->join('appointments as a', 'a.id', '=', 'asv.appointment_id')
            ->where('a.salon_id', $salon->id)
            ->where('a.status', 'completed')
            ->whereDate('a.appointment_date', '>=', $from)
            ->whereDate('a.appointment_date', '<=', $to)
            ->groupBy('asv.service_id')
            ->selectRaw('asv.service_id, COUNT(*) as bookings')
            ->pluck('bookings', 'asv.service_id');

        $recent = $counts(now()->subDays(29)->toDateString(), now()->toDateString());
        $before = $counts(now()->subDays(59)->toDateString(), now()->subDays(30)->toDateString());

        $services = DB::table('services as s')
            ->leftJoin('service_templates as t', 't.id', '=', 's.template_id')
            ->where('s.salon_id', $salon->id)
            ->whereNull('s.deleted_at')
            ->where('s.created_at', '<=', now()->subDays(60))
            ->selectRaw("s.id, COALESCE(t.name, 'Custom service') as name")
            ->get();

        $alerts = [];
        foreach ($services as $service) {
            $now = (int) ($recent[$service->id] ?? 0);
            $then = (int) ($before[$service->id] ?? 0);

            if ($now === 0 && $then === 0) {
                $alerts[] = [
                    'service_id' => $service->id, 'name' => $service->name,
                    'last_30_days' => 0, 'previous_30_days' => 0, 'change_percent' => null,
                    'kind' => 'unbooked',
                    'suggestion' => "No one has booked {$service->name} in 60 days. Put it in a combo with a popular service, review the price, or remove it.",
                ];
            } elseif ($then >= 3 && $now <= $then * 0.7) {
                $change = round(($now - $then) / $then * 100, 1);
                $alerts[] = [
                    'service_id' => $service->id, 'name' => $service->name,
                    'last_30_days' => $now, 'previous_30_days' => $then, 'change_percent' => $change,
                    'kind' => 'falling',
                    'suggestion' => "{$service->name} bookings fell from {$then} to {$now}. A short offer or adding it as an upsell could bring it back.",
                ];
            }
        }

        return collect($alerts)->sortBy(fn ($a) => $a['kind'] === 'falling' ? 0 : 1)->take(8)->values()->all();
    }

    /**
     * Regulars who have stopped coming, with the number to call them on.
     * Highest spenders first: they are the ones worth a phone call.
     */
    public function winBack(Salon $salon, int $limit = 25): array
    {
        $inactiveAfter = $this->settings->inactiveDays();
        $cutoff = now()->subDays($inactiveAfter);

        return $this->customerRows($salon, now()->subDays(365)->toDateString())
            ->filter(fn ($row) => (int) $row->visits >= 2
                && $row->phone
                && $row->last_visit
                && Carbon::parse($row->last_visit)->lt($cutoff))
            ->sortByDesc(fn ($row) => (float) $row->spend)
            ->take($limit)
            ->map(fn ($row) => [
                'name' => $row->name ?: 'Customer',
                'phone' => $row->phone,
                'visits' => (int) $row->visits,
                'spend' => round((float) $row->spend, 2),
                'last_visit' => $row->last_visit,
                'days_since' => (int) Carbon::parse($row->last_visit)->startOfDay()->diffInDays(now()->startOfDay()),
            ])->values()->all();
    }

    /**
     * One row per customer of this salon, aggregated over their visits.
     *
     * The same COALESCE shape as the audience builder, and for the same reason:
     * a walk-in is a customer, and an insight that counted only account holders
     * would quietly describe a different salon.
     */
    private function customerRows(Salon $salon, string $since)
    {
        return DB::table('appointments as a')
            ->leftJoin('users as u', 'u.id', '=', 'a.customer_id')
            ->where('a.salon_id', $salon->id)
            ->where('a.status', 'completed')
            ->whereDate('a.appointment_date', '>=', $since)
            ->where(function ($q) {
                $q->whereNotNull('u.phone')
                  ->orWhereNotNull('a.walk_in_customer_phone')
                  ->orWhereNotNull('a.walk_in_customer_name')
                  ->orWhereNotNull('a.customer_id');
            })
            ->groupBy(DB::raw("COALESCE(u.phone, a.walk_in_customer_phone, a.walk_in_customer_name, CAST(a.id AS VARCHAR))"))
            ->selectRaw(
                'MAX(COALESCE(u.name, a.walk_in_customer_name, \'Walk-in Customer\')) as name, '
                .'COUNT(*) as visits, '
                .'COALESCE(SUM(COALESCE(a.final_billed_amount, a.total_amount)), 0) as spend, '
                .'MAX(a.appointment_date) as last_visit, '
                .'MAX(COALESCE(u.phone, a.walk_in_customer_phone)) as phone'
            )
            ->get();
    }

    private function hourLabel(int $hour): string
    {
        $suffix = $hour < 12 ? 'am' : 'pm';
        $display = $hour % 12 === 0 ? 12 : $hour % 12;

        return $display.$suffix;
    }
}
