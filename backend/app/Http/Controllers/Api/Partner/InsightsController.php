<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\Salon;
use App\Services\Marketing\CampaignEntitlementService;
use App\Services\Marketing\SalonInsightsService;
use Illuminate\Http\Request;

/**
 * The growth insights, with the plan's ceiling applied.
 *
 * Starter is "know your salon": the headline numbers, the 30-day trend, its
 * services and staff, retention, and basic upsell and cross-sell tips. Growth
 * is "grow your revenue": longer history, who is slipping away, when the chairs
 * are empty, who the customers are, and concrete ideas for earning more.
 *
 * Locked sections are named in the response rather than omitted from it. The
 * app draws them greyed out with an upgrade prompt, which is the only honest
 * way to show someone what they are not getting.
 */
class InsightsController extends Controller
{
    /** History windows Growth can switch between. Starter always sees 30 days. */
    private const PERIODS = [30, 90, 365];

    public function __construct(
        private SalonInsightsService $insights,
        private CampaignEntitlementService $entitlements,
    ) {
    }

    public function show(Request $request, string $salonId)
    {
        $user = $request->user();
        if ($user->role === 'superadmin') {
            $salon = Salon::findOrFail($salonId);
        } else {
            $salon = Salon::where('admin_id', $user->id)->findOrFail($salonId);
        }

        $plan = $this->entitlements->activeSubscription($salon)?->plan;

        // Only BookALook's own staff look past the plan. A salon owner sees
        // exactly what their plan includes, with the rest drawn as locked.
        $isSuperAdmin = $user->role === 'superadmin';
        $advanced = $isSuperAdmin || (bool) ($plan->has_advanced_insights ?? false);
        $upsellLevel = $isSuperAdmin ? 'advanced' : $this->level($plan, 'has_upsell_recommendations');
        $crossSellLevel = $isSuperAdmin ? 'advanced' : $this->level($plan, 'has_cross_sell_recommendations');

        $days = (int) $request->query('days', 30);
        $days = $advanced && in_array($days, self::PERIODS, true) ? $days : 30;

        $payload = [
            'plan_name' => $plan->name ?? ($isSuperAdmin ? 'Admin Full Access' : null),
            'advanced' => $advanced,
            'periods' => $advanced ? self::PERIODS : [30],

            // Every plan.
            'overview' => $this->insights->overview($salon),
            'services' => $this->insights->services($salon),
            'basic_analytics' => [
                'revenue_trend' => $this->insights->revenueTrend($salon, 30),
                'staff_performance' => $this->insights->staffPerformance($salon, 30),
            ],
            'retention_funnel' => $this->insights->retentionFunnel($salon),
        ];

        // Basic cross-sell is the top three pairs; advanced is every pair with
        // the revenue behind it. The service ids and whether a combo already
        // exists are kept at both levels, because the "create this combo"
        // button needs them to work at all.
        if ($crossSellLevel !== 'none') {
            $payload['cross_sell'] = $crossSellLevel === 'advanced'
                ? $this->insights->pairs($salon)
                : collect($this->insights->pairs($salon, 3))
                    ->map(fn (array $pair) => [
                        'services' => $pair['services'],
                        'service_ids' => $pair['service_ids'],
                        'booked_together' => $pair['booked_together'],
                        'already_a_combo' => $pair['already_a_combo'],
                    ])->all();
        }

        // Basic upsell is the top two trade-ups, without the rupee figure.
        if ($upsellLevel !== 'none') {
            $suggestions = $this->insights->upsell($salon);
            $payload['upsell'] = $upsellLevel === 'advanced'
                ? $suggestions
                : collect(array_slice($suggestions, 0, 2))
                    ->map(fn (array $s) => ['from' => $s['from'], 'to' => $s['to'], 'evidence' => $s['evidence']])
                    ->all();
        }

        if ($advanced) {
            $payload['period'] = $this->insights->periodComparison($salon, $days);
            $payload['repeat_customers'] = $this->insights->repeatCustomers($salon);
            $payload['peak_hours'] = $this->insights->peakHours($salon);
            $payload['areas'] = $this->insights->areas($salon);
            $payload['gender_mix'] = $this->insights->genderMix($salon);
            $payload['visit_gap'] = $this->insights->visitGap($salon);
            $payload['staff_deep_dive'] = $this->insights->staffDeepDive($salon);
            $payload['recommended_combos'] = $this->insights->recommendedCombos($salon);
            $payload['upsell_links'] = $this->insights->upsellLinkPerformance($salon);
            $payload['quiet_hour_offers'] = $this->insights->quietHourOffers($salon);
            $payload['slow_services'] = $this->insights->slowServices($salon);
            $payload['win_back'] = $this->insights->winBack($salon);
        }

        return response()->json([
            'success' => true,
            'data' => $payload,
            'locked' => $isSuperAdmin ? [] : $this->lockedSections($advanced, $upsellLevel, $crossSellLevel),
        ]);
    }

    /**
     * A plan's upsell or cross-sell level. Any plan gets at least the basic
     * version, because Starter's basic suggestions are part of what it sells.
     */
    private function level($plan, string $column): string
    {
        if (! $plan) {
            return 'none';
        }

        return ($plan->{$column} ?? 'none') === 'advanced' ? 'advanced' : 'basic';
    }

    /**
     * What this plan is not showing, in the words the app puts on the card.
     *
     * @return array<int, array<string, string>>
     */
    private function lockedSections(bool $advanced, string $upsell, string $crossSell): array
    {
        $locked = [];

        if (! $advanced) {
            foreach ([
                ['period', 'Longer history', 'Compare 30, 90 and 365 days with the period before.'],
                ['peak_hours', 'Peak & quiet hours', 'See your busy and empty hours by day of the week.'],
                ['repeat_customers', 'Repeat customers', 'See who your regulars are and who has stopped coming back.'],
                ['areas', 'Customer areas', 'See which neighbourhoods your customers come from.'],
                ['gender_mix', 'Customer mix', 'How each service splits between men and women.'],
                ['visit_gap', 'Average bill & visit gap', 'What a visit is worth and how long customers wait before coming back.'],
                ['staff_deep_dive', 'Staff deep-dive', 'Average bill, repeat rate and no-shows for each provider.'],
                ['recommended_combos', 'Recommended combos', 'Combos worth creating, based on what customers already book together.'],
                ['upsell_links', 'Upsell link performance', 'How often your upsell links are actually added at booking.'],
                ['quiet_hour_offers', 'Quiet-hour offer ideas', 'Offer ideas for your emptiest hours.'],
                ['slow_services', 'Slow-service alerts', 'Services losing bookings, and what to do about them.'],
                ['win_back', 'Win-back list', 'Regulars who stopped coming, with their numbers to call.'],
            ] as [$key, $name, $reason]) {
                $locked[] = ['key' => $key, 'name' => $name, 'reason' => $reason];
            }
        }

        if ($crossSell !== 'advanced') {
            $locked[] = ['key' => 'cross_sell_advanced', 'name' => 'Full cross-sell',
                'reason' => 'Every pair booked together, with the revenue behind it, not just the top three.'];
        }

        if ($upsell !== 'advanced') {
            $locked[] = ['key' => 'upsell_advanced', 'name' => 'Full upsell tips',
                'reason' => 'Every trade-up your customers already make, with the extra rupees each one brings.'];
        }

        return $locked;
    }
}
