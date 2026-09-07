<?php

namespace App\Services;

use App\Models\Cart;
use App\Models\Combo;
use App\Models\Service;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Prices a cart, applying the salon's combo packages automatically.
 *
 * A customer who happens to pick every service in a package should pay the
 * package price without having to know the package exists. So the combo is
 * matched against the loose service lines and applied silently — the cart is
 * never re-shaped, only re-priced, which means removing one service quietly
 * reverts to list prices with no cleanup.
 *
 * This is the single source of truth: the cart screen, the checkout totals and
 * what the booking actually charges all read the same numbers, so a customer
 * can never be shown one price and billed another.
 */
class CartPricingService
{
    /** Fallback advance % when neither service nor combo defines one. */
    public const DEFAULT_ADVANCE_PERCENTAGE = AvailabilityService::DEFAULT_ADVANCE_PERCENTAGE;

    /**
     * Everything the cart is worth, and why.
     *
     * @return array{
     *   service_ids: string[], duration: int, total: float, list_total: float,
     *   saving: float, advance: float, item_count: int,
     *   applied_combos: array, loose_services: array
     * }
     */
    public function price(Cart $cart): array
    {
        $cart->loadMissing(['items.service.template', 'items.combo.services.template']);

        // Quantities of each loose service — what combos are matched against.
        $loose = [];
        foreach ($cart->items as $item) {
            if (! $item->service) {
                continue;
            }

            $loose[$item->service_id] = ($loose[$item->service_id] ?? 0) + max(1, (int) $item->quantity);
        }

        $serviceById = $cart->items
            ->filter(fn ($item) => $item->service)
            ->mapWithKeys(fn ($item) => [$item->service_id => $item->service]);

        $applied = $this->applyCombos($cart->salon_id, $loose, $serviceById);

        $total = 0.0;
        $listTotal = 0.0;
        $advance = 0.0;
        $duration = 0;
        $serviceIds = [];
        $itemCount = 0;

        // 1. Combos matched out of loose services.
        foreach ($applied['combos'] as $match) {
            $total += $match['combo_total'];
            $listTotal += $match['list_total'];
            $advance += $match['combo_total'] * $this->advancePercentage($match['advance_percentage']) / 100;

            foreach ($match['services'] as $line) {
                $duration += $line['duration_minutes'] * $match['applications'];
                $serviceIds[] = $line['service_id'];
                $itemCount += $match['applications'];
            }
        }

        // 2. Whatever the combos did not absorb, at list price.
        $looseLines = [];
        foreach ($applied['remaining'] as $serviceId => $quantity) {
            if ($quantity < 1) {
                continue;
            }

            $service = $serviceById[$serviceId];
            $price = (float) $service->price * $quantity;

            $total += $price;
            $listTotal += $price;
            $advance += $price * $this->advancePercentage($service->advance_percentage) / 100;
            $duration += $this->serviceDuration($service) * $quantity;
            $serviceIds[] = $serviceId;
            $itemCount += $quantity;

            $looseLines[] = [
                'service_id' => $serviceId,
                'name' => $service->template->name ?? 'Service',
                'price' => (float) $service->price,
                'quantity' => $quantity,
            ];
        }

        // 3. Packages the customer picked deliberately, priced as they always were.
        foreach ($cart->items as $item) {
            if (! $item->combo) {
                continue;
            }

            $quantity = max(1, (int) $item->quantity);
            $comboTotal = 0.0;
            $comboList = 0.0;

            foreach ($item->combo->services as $service) {
                $comboTotal += (float) ($service->pivot->combo_special_price ?? $service->price) * $quantity;
                $comboList += (float) $service->price * $quantity;
                $duration += $this->serviceDuration($service) * $quantity;
                $serviceIds[] = $service->id;
            }

            $total += $comboTotal;
            $listTotal += $comboList;
            $advance += $comboTotal * $this->advancePercentage($item->combo->advance_percentage) / 100;
            $itemCount += $quantity;
        }

        return [
            'service_ids' => array_values(array_unique($serviceIds)),
            'duration' => max($duration, AvailabilityService::SLOT_MINUTES),
            'total' => round($total, 2),
            'list_total' => round($listTotal, 2),
            'saving' => round(max($listTotal - $total, 0), 2),
            'advance' => round(min($advance, $total), 2),
            'item_count' => $itemCount,
            'applied_combos' => $applied['combos'],
            'loose_services' => $looseLines,
        ];
    }

    /**
     * Packages the customer is close to completing.
     *
     * Only combos where at least one service is already in the cart — otherwise
     * this is an advert, not a nudge. The cost quoted is what the missing
     * services add, and the saving is what completing it is worth over buying
     * everything loose.
     *
     * @param  array<string, int>  $cartServiceIds
     * @return array<int, array>
     */
    public function comboOffers(Cart $cart): array
    {
        $cart->loadMissing(['items.service']);

        $inCart = $cart->items
            ->filter(fn ($item) => $item->service)
            ->pluck('service_id')
            ->unique()
            ->all();

        if (empty($inCart)) {
            return [];
        }

        $priced = $this->price($cart);
        $alreadyApplied = collect($priced['applied_combos'])->pluck('combo_id')->all();

        $offers = [];

        foreach ($this->combosFor($cart->salon_id) as $combo) {
            if (in_array($combo->id, $alreadyApplied, true)) {
                continue;
            }

            $comboServiceIds = $combo->services->pluck('id')->all();
            $have = array_intersect($comboServiceIds, $inCart);
            $missing = array_diff($comboServiceIds, $inCart);

            // Needs a foothold, and something still to add.
            if (empty($have) || empty($missing)) {
                continue;
            }

            $missingServices = $combo->services->whereIn('id', $missing);

            $comboTotal = (float) $combo->services->sum(
                fn ($s) => (float) ($s->pivot->combo_special_price ?? $s->price)
            );
            $listTotal = (float) $combo->services->sum(fn ($s) => (float) $s->price);

            // What they would pay today for the part they already hold.
            $alreadyPaying = (float) $combo->services->whereIn('id', $have)->sum(fn ($s) => (float) $s->price);

            $offers[] = [
                'combo_id' => $combo->id,
                'name' => $combo->name,
                'services_in_cart' => $combo->services->whereIn('id', $have)
                    ->map(fn ($s) => $s->template->name ?? 'Service')->values()->all(),
                'missing_services' => $missingServices->map(fn ($s) => [
                    'id' => $s->id,
                    'name' => $s->template->name ?? 'Service',
                    'price' => (float) $s->price,
                    'combo_price' => (float) ($s->pivot->combo_special_price ?? $s->price),
                    'duration_minutes' => $this->serviceDuration($s),
                ])->values()->all(),
                'combo_total' => round($comboTotal, 2),
                'list_total' => round($listTotal, 2),
                'saving' => round(max($listTotal - $comboTotal, 0), 2),
                // The extra outlay to complete the package from here.
                'extra_to_pay' => round(max($comboTotal - $alreadyPaying, 0), 2),
            ];
        }

        // Best value first.
        usort($offers, fn ($a, $b) => $b['saving'] <=> $a['saving']);

        return $offers;
    }

    /**
     * Services this salon's customers actually book alongside what is in the
     * cart, most common first.
     *
     * Falls back to the same categories when the salon has no history yet — a
     * new salon should still suggest something sensible.
     *
     * @return array<int, array>
     */
    public function suggestions(Cart $cart, int $limit = 6): array
    {
        $cart->loadMissing(['items.service.template', 'items.combo.services']);

        $inCart = $this->allServiceIdsIn($cart);

        if (empty($inCart)) {
            return [];
        }

        $together = $this->boughtTogether($cart->salon_id, $inCart, $limit);

        if (count($together) >= $limit) {
            return $together;
        }

        // Top up with same-category services so the strip is never near-empty.
        $exclude = array_merge($inCart, array_column($together, 'id'));

        return array_merge($together, $this->sameCategory($cart->salon_id, $inCart, $exclude, $limit - count($together)));
    }

    // ------------------------------------------------------------- internals

    /**
     * Greedily match combos against the loose services, best saving first.
     *
     * Exact set-packing is overkill for a handful of packages, and taking the
     * biggest saving first is both cheap and the answer a customer would argue
     * for anyway.
     *
     * @param  array<string, int>  $loose
     * @return array{combos: array, remaining: array<string, int>}
     */
    private function applyCombos(string $salonId, array $loose, Collection $serviceById): array
    {
        $remaining = $loose;
        $matched = [];

        $candidates = [];

        foreach ($this->combosFor($salonId) as $combo) {
            $ids = $combo->services->pluck('id')->all();

            // A one-service "combo" is just a price, not a package.
            if (count($ids) < 2) {
                continue;
            }

            $comboTotal = (float) $combo->services->sum(
                fn ($s) => (float) ($s->pivot->combo_special_price ?? $s->price)
            );
            $listTotal = (float) $combo->services->sum(fn ($s) => (float) $s->price);

            $candidates[] = [
                'combo' => $combo,
                'ids' => $ids,
                'combo_total' => $comboTotal,
                'saving' => $listTotal - $comboTotal,
                'list_total' => $listTotal,
            ];
        }

        usort($candidates, fn ($a, $b) => $b['saving'] <=> $a['saving']);

        foreach ($candidates as $candidate) {
            // How many complete sets the cart holds.
            $applications = null;

            foreach ($candidate['ids'] as $id) {
                $held = $remaining[$id] ?? 0;
                $applications = $applications === null ? $held : min($applications, $held);
            }

            if (! $applications || $applications < 1 || $candidate['saving'] <= 0) {
                continue;
            }

            foreach ($candidate['ids'] as $id) {
                $remaining[$id] -= $applications;
            }

            $combo = $candidate['combo'];

            $matched[] = [
                'combo_id' => $combo->id,
                'name' => $combo->name,
                'applications' => $applications,
                'advance_percentage' => $combo->advance_percentage,
                'combo_total' => round($candidate['combo_total'] * $applications, 2),
                'list_total' => round($candidate['list_total'] * $applications, 2),
                'saving' => round($candidate['saving'] * $applications, 2),
                'services' => $combo->services->map(fn ($s) => [
                    'service_id' => $s->id,
                    'name' => $s->template->name ?? 'Service',
                    'list_price' => (float) $s->price,
                    'combo_price' => (float) ($s->pivot->combo_special_price ?? $s->price),
                    'duration_minutes' => $this->serviceDuration($s),
                ])->values()->all(),
            ];
        }

        return ['combos' => $matched, 'remaining' => $remaining];
    }

    /** @return Collection<int, Combo> */
    private function combosFor(string $salonId): Collection
    {
        return Combo::with('services.template')
            ->where('salon_id', $salonId)
            ->where('is_active', true)
            ->get();
    }

    /** Every service id the cart holds, loose or inside a chosen package. */
    private function allServiceIdsIn(Cart $cart): array
    {
        $ids = [];

        foreach ($cart->items as $item) {
            if ($item->service) {
                $ids[] = $item->service_id;
            }

            if ($item->combo) {
                foreach ($item->combo->services as $service) {
                    $ids[] = $service->id;
                }
            }
        }

        return array_values(array_unique($ids));
    }

    /**
     * @param  string[]  $inCart
     * @return array<int, array>
     */
    private function boughtTogether(string $salonId, array $inCart, int $limit): array
    {
        // How many completed appointments contained each cart service, so the
        // suggestion can be expressed as a share rather than a raw count.
        $baseline = (int) DB::table('appointment_services as mine')
            ->join('appointments as a', 'a.id', '=', 'mine.appointment_id')
            ->where('a.salon_id', $salonId)
            ->where('a.status', 'completed')
            ->whereIn('mine.service_id', $inCart)
            ->distinct()
            ->count('a.id');

        if ($baseline === 0) {
            return [];
        }

        $rows = DB::table('appointment_services as mine')
            ->join('appointments as a', 'a.id', '=', 'mine.appointment_id')
            ->join('appointment_services as other', function ($join) {
                $join->on('other.appointment_id', '=', 'a.id')
                    ->whereColumn('other.service_id', '!=', 'mine.service_id');
            })
            ->join('services as s', 's.id', '=', 'other.service_id')
            ->join('service_templates as t', 't.id', '=', 's.template_id')
            ->where('a.salon_id', $salonId)
            ->where('a.status', 'completed')
            ->whereIn('mine.service_id', $inCart)
            ->whereNotIn('other.service_id', $inCart)
            ->where('s.is_active', true)
            ->whereNull('s.deleted_at')
            ->groupBy('other.service_id', 't.name', 's.price')
            ->orderByDesc(DB::raw('COUNT(DISTINCT a.id)'))
            ->limit($limit)
            ->get([
                'other.service_id as id',
                't.name as name',
                's.price as price',
                DB::raw('COUNT(DISTINCT a.id) as together_count'),
            ]);

        return $rows->map(fn ($row) => [
            'id' => $row->id,
            'name' => $row->name,
            'price' => (float) $row->price,
            'reason' => 'bought_together',
            'together_count' => (int) $row->together_count,
            'together_percent' => (int) round($row->together_count / $baseline * 100),
        ])->all();
    }

    /**
     * @param  string[]  $inCart
     * @param  string[]  $exclude
     * @return array<int, array>
     */
    private function sameCategory(string $salonId, array $inCart, array $exclude, int $limit): array
    {
        if ($limit < 1) {
            return [];
        }

        $categoryIds = Service::with('template')
            ->whereIn('id', $inCart)
            ->get()
            ->pluck('template.category_id')
            ->filter()
            ->unique()
            ->all();

        if (empty($categoryIds)) {
            return [];
        }

        return Service::with('template')
            ->where('salon_id', $salonId)
            ->where('is_active', true)
            ->whereNotIn('id', $exclude)
            ->whereHas('template', fn ($q) => $q->whereIn('category_id', $categoryIds))
            ->orderBy('display_order')
            ->limit($limit)
            ->get()
            ->map(fn (Service $service) => [
                'id' => $service->id,
                'name' => $service->template->name ?? 'Service',
                'price' => (float) $service->price,
                'reason' => 'same_category',
                'together_count' => 0,
                'together_percent' => 0,
            ])
            ->all();
    }

    private function serviceDuration($service): int
    {
        return (int) ($service->template->estimated_duration_minutes ?? AvailabilityService::SLOT_MINUTES);
    }

    private function advancePercentage($value): float
    {
        return $value === null ? self::DEFAULT_ADVANCE_PERCENTAGE : (float) $value;
    }
}
