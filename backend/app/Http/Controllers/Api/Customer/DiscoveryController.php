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
            ->selectRaw('t.id as service_id')
            ->selectRaw('t.name')
            ->selectRaw('t.estimated_duration_minutes as duration_minutes')
            ->selectRaw('MIN(sv.price) as min_price')
            ->selectRaw('COUNT(DISTINCT s.id) as salon_count')
            ->groupBy('t.id', 't.name', 't.estimated_duration_minutes')
            ->orderBy('t.name')
            ->get();

        return response()->json([
            'services' => $rows->map(fn ($row) => [
                'service_id' => $row->service_id,
                'name' => $row->name,
                'duration_minutes' => (int) $row->duration_minutes,
                'min_price' => round((float) $row->min_price, 2),
                'salon_count' => (int) $row->salon_count,
            ])->values(),
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

        $rows = Combo::with('services:id,price')
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
        ]);

        $grouped = $priced->groupBy('name')
            ->map(fn (Collection $items, string $name) => [
                'name' => $name,
                'salon_count' => (int) $items->count(),
                'starting_price' => round((float) $items->min('price'), 2),
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
}