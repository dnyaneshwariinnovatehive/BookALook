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
            ->whereNotNull(DB::raw('COALESCE(u.phone, a.walk_in_customer_phone)'))
            ->groupBy(DB::raw('COALESCE(u.phone, a.walk_in_customer_phone)'))
            ->selectRaw(
                'MAX(COALESCE(u.name, a.walk_in_customer_name)) as name, '
                .'COUNT(*) as visits, '
                .'COALESCE(SUM(COALESCE(a.final_billed_amount, a.total_amount)), 0) as spend, '
                .'MAX(a.appointment_date) as last_visit'
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
