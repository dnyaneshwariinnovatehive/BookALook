<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\City;
use App\Models\Combo;
use App\Models\Service;
use App\Models\ServiceCategory;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * The discovery catalogue behind the category and combo search screens: the
 * distinct services a category is genuinely offering in the city, and every
 * combo package name on the market. Both are public like /salons so a guest
 * deciding whether to install sees the same real catalogue as a signed-in
 * customer, and neither ever invents an offering the backend cannot prove.
 */
class DiscoveryController extends Controller
{
    /**
     * Distinct catalogue services actually on offer for a category, with real
     * prices, so the horizontal scroller is honest before anyone opens a salon.
     *
     * Each service also carries the exact salon that best represents it — the
     * highest-rated active salon in the city offering that service — together
     * with that salon's own offer id, price and rating. The app uses those to
     * put a named salon on every top-rated card and to add that exact
     * salon + service to the cart in one tap, without ever inventing a host.
     */
    public function servicesByCategory(Request $request, string $categoryId)
    {
        $category = ServiceCategory::where('id', $categoryId)
            ->where('is_active', true)
            ->first();

        if (! $category) {
            return response()->json(['message' => 'Category not found.'], 404);
        }

        $city = $this->resolveCity($request);

        $rows = DB::table('services as sv')
            ->join('service_templates as t', 't.id', '=', 'sv.template_id')
            ->join('salons as s', 's.id', '=', 'sv.salon_id')
            ->where('t.category_id', $category->id)
            ->where('sv.is_active', true)
            ->whereNull('sv.deleted_at')
            ->where('s.status', 'active')
            ->whereNull('s.deleted_at')
            ->when($city, fn ($q) => $q->where('s.city_id', $city->id))
            ->selectRaw('sv.id as offer_id')
            ->selectRaw('sv.template_id as service_id')
            ->selectRaw('t.name')
            ->selectRaw('t.estimated_duration_minutes as duration_minutes')
            ->selectRaw('sv.price')
            ->selectRaw('s.id as salon_id')
            ->selectRaw('s.name as salon_name')
            ->selectRaw('s.cover_photo_url as salon_cover_url')
            ->selectRaw('s.avg_rating as rating')
            // Highest-rated host first (unrated salons last), cheapest price a
            // tie-breaker, then a stable id so "top" is deterministic.
            ->orderBy('sv.template_id')
            ->orderByRaw('ISNULL(s.avg_rating), s.avg_rating DESC, sv.price ASC, sv.id ASC')
            ->get();

        $services = $rows
            ->groupBy('service_id')
            ->map(function (Collection $offers) {
                $top = $offers->first();

                return [
                    'service_id' => $top->service_id,
                    'name' => $top->name,
                    'duration_minutes' => (int) $top->duration_minutes,
                    'min_price' => round((float) $offers->min('price'), 2),
                    'price' => round((float) $top->price, 2),
                    'offer_id' => $top->offer_id,
                    'salon_id' => $top->salon_id,
                    'salon_name' => $top->salon_name,
                    'salon_cover_url' => $top->salon_cover_url,
                    'salon_count' => (int) $offers->unique('salon_id')->count(),
                    'rating' => $top->rating !== null ? round((float) $top->rating, 1) : null,
                ];
            })
            ->sortBy('name')
            ->values();

        return response()->json([
            'services' => $services,
            'city' => $this->cityPayload($city),
        ]);
    }

    /**
     * Every combo package name in the city, once, with how many salons offer
     * it and the cheapest price across them.
     */
    public function combos(Request $request)
    {
        $city = $this->resolveCity($request);

        $rows = Combo::with(['services:id,price', 'salon:id,avg_rating'])
            ->where('is_active', true)
            ->whereHas('salon', function ($q) use ($city) {
                $q->where('status', 'active');

                if ($city) {
                    $q->where('city_id', $city->id);
                }
            })
            ->get(['id', 'salon_id', 'name']);

        $priced = $rows->map(fn (Combo $combo) => [
            'name' => trim($combo->name),
            'price' => (float) $combo->services->sum(function (Service $service) {
                return (float) ($service->pivot->combo_special_price ?? $service->price);
            }),
            'rating' => $combo->salon?->avg_rating,
        ]);

        $grouped = $priced->groupBy('name')
            ->map(fn (Collection $items, string $name) => [
                'name' => $name,
                'salon_count' => (int) $items->count(),
                'starting_price' => round((float) $items->min('price'), 2),
                'rating' => $this->bestSalonRating($items),
            ])
            ->sortBy('name')
            ->values();

        return response()->json([
            'combos' => $grouped,
            'city' => $this->cityPayload($city),
        ]);
    }

    /**
     * Which city's catalogue to show. Same precedence the salon directory
     * uses, so the scroller and the salon list always agree on "near you".
     */
    private function resolveCity(Request $request): ?City
    {
        if ($request->filled('city_id')) {
            $chosen = City::find($request->city_id);

            if ($chosen) {
                return $chosen;
            }
        }

        $saved = auth('sanctum')->user()?->city;

        if ($saved) {
            return $saved;
        }

        $geo = app(\App\Services\GeoService::class);

        if ($geo->isValid($request->lat, $request->lng)) {
            $market = $geo->marketFor((float) $request->lat, (float) $request->lng);

            if ($market['city']) {
                return $market['city'];
            }
        }

        return City::where('is_active', true)
            ->serviceable()
            ->withOpenSalonCount()
            ->orderByDesc('salon_count')
            ->first();
    }

    private function cityPayload(?City $city): ?array
    {
        return $city ? [
            'id' => $city->id,
            'name' => $city->name,
            'state' => $city->state,
        ] : null;
    }

    /**
     * The highest salon rating earned by any salon offering this combo name,
     * so the top-rated scroller ranks real market packages by their best host.
     */
    private function bestSalonRating(Collection $items): ?float
    {
        $rating = $items
            ->map(fn (array $item) => $item['rating'])
            ->filter()
            ->max();

        return $rating === null ? null : round((float) $rating, 1);
    }
}