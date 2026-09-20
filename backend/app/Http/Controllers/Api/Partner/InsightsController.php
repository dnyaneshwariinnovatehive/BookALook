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
 * Every salon that is paying gets the headline numbers, its own services and a
 * basic view of what sells together — a salon cannot be asked to grow on no
 * information at all. Growth adds the parts that need real analysis: who is
 * slipping away, when the chairs are empty, where the customers live, and what
 * to package or trade up.
 *
 * Locked sections are named in the response rather than omitted from it. The
 * app draws them greyed out with an upgrade prompt, which is what the plan
 * spec asks for and also the only honest way to show someone what they are not
 * getting.
 */
class InsightsController extends Controller
{
    public function __construct(
        private SalonInsightsService $insights,
        private CampaignEntitlementService $entitlements,
    ) {
    }

    public function show(Request $request, string $salonId)
    {
        $salon = Salon::where('admin_id', $request->user()->id)->findOrFail($salonId);
        $plan = $this->entitlements->activeSubscription($salon)?->plan;

        $advanced = (bool) ($plan->has_advanced_insights ?? false);
        $upsellLevel = $plan->has_upsell_recommendations ?? 'none';
        $crossSellLevel = $plan->has_cross_sell_recommendations ?? 'none';

        $payload = [
            'plan_name' => $plan->name ?? null,
            'advanced' => $advanced,

            // Always available to a paying salon.
            'overview' => $this->insights->overview($salon),
            'services' => $this->insights->services($salon),
            'campaigns' => $this->insights->campaignPerformance($salon),
        ];

        // Basic cross-sell is the top few pairs and nothing more; advanced adds
        // the revenue behind each one and the combos worth building from them.
        if ($crossSellLevel !== 'none') {
            $payload['cross_sell'] = $crossSellLevel === 'advanced'
                ? $this->insights->pairs($salon)
                : collect($this->insights->pairs($salon, 3))
                    ->map(fn (array $pair) => [
                        'services' => $pair['services'],
                        'booked_together' => $pair['booked_together'],
                    ])->all();
        }

        if ($upsellLevel !== 'none') {
            $suggestions = $this->insights->upsell($salon);
            $payload['upsell'] = $upsellLevel === 'advanced'
                ? $suggestions
                : array_slice($suggestions, 0, 2);
        }

        if ($advanced) {
            $payload['repeat_customers'] = $this->insights->repeatCustomers($salon);
            $payload['peak_hours'] = $this->insights->peakHours($salon);
            $payload['areas'] = $this->insights->areas($salon);
            $payload['recommended_combos'] = $this->insights->recommendedCombos($salon);
        }

        return response()->json([
            'success' => true,
            'data' => $payload,
            'locked' => $this->lockedSections($advanced, $upsellLevel, $crossSellLevel),
        ]);
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
            $locked[] = ['key' => 'repeat_customers', 'name' => 'Repeat-customer insights',
                'reason' => 'See who your regulars are and who has stopped coming back.'];
            $locked[] = ['key' => 'peak_hours', 'name' => 'Peak-hour insights',
                'reason' => 'Find your quiet hours so you know when an offer is worth sending.'];
            $locked[] = ['key' => 'areas', 'name' => 'Customer-area insights',
                'reason' => 'See which neighbourhoods your customers come from.'];
            $locked[] = ['key' => 'recommended_combos', 'name' => 'Recommended combos',
                'reason' => 'Combos worth creating, based on what customers already book together.'];
        }

        if ($crossSell !== 'advanced') {
            $locked[] = ['key' => 'cross_sell_advanced', 'name' => 'Advanced cross-sell',
                'reason' => 'The revenue behind every pair, not just the top three.'];
        }

        if ($upsell !== 'advanced') {
            $locked[] = ['key' => 'upsell_advanced', 'name' => 'Advanced upsell',
                'reason' => 'Every trade-up your customers already make, with the uplift on each.'];
        }

        return $locked;
    }
}
