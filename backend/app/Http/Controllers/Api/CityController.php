<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\City;
use App\Services\GeoService;
use Illuminate\Http\Request;

class CityController extends Controller
{
    /**
     * The city list.
     *
     * Two audiences with opposite needs. SuperAdmin and partner onboarding want
     * every city, because a salon can register anywhere. The customer app wants
     * only the cities it can actually serve — offering the rest sends a customer
     * to an empty screen, and one empty screen is enough to decide the app has
     * nothing in it.
     *
     * So the full list stays the default, and `?serviceable=1` narrows it.
     */
    public function index(Request $request)
    {
        $query = City::where('is_active', true);

        if ($request->boolean('serviceable')) {
            $query->serviceable();
        }

        if ($request->filled('search')) {
            $search = $request->input('search');
            $query->where(fn ($q) => $q->where('name', 'like', "%{$search}%")
                ->orWhere('state', 'like', "%{$search}%"));
        }

        $cities = $query->withOpenSalonCount()
            // Busiest markets first: the city a customer wants is usually the
            // one with the most in it, and alphabetical buries it.
            ->orderByDesc('salon_count')
            ->orderBy('name')
            ->get();

        return response()->json($cities);
    }

    /**
     * The localities inside one city.
     *
     * Open to everyone, because every form that asks for an address needs it —
     * the public enquiry form, customer sign-up, a salon registering itself,
     * and a collaborator onboarding one. All of those run before there is
     * anybody to authenticate.
     *
     * `?serviceable=1` narrows it to localities that actually have an open
     * salon, which is what a customer picking where to browse should see. The
     * full list is the default, because a salon can register in a locality that
     * has none yet — that is the point of registering.
     */
    public function subAreas(Request $request, string $cityId)
    {
        $city = City::find($cityId);

        if (! $city) {
            return response()->json(['success' => false, 'message' => 'City not found.'], 404);
        }

        $query = $city->subAreas()->active();

        if ($request->boolean('serviceable')) {
            $query->whereExists(
                fn ($sub) => $sub->selectRaw(1)
                    ->from('salons')
                    ->whereColumn('salons.sub_area_id', 'sub_areas.id')
                    ->where('salons.status', 'active')
                    ->whereNull('salons.deleted_at')
            );
        }

        return response()->json([
            'success' => true,
            'city' => ['id' => $city->id, 'name' => $city->name, 'state' => $city->state],
            'sub_areas' => $query->get(['id', 'name']),
        ]);
    }

    /**
     * Which market a coordinate belongs to.
     *
     * The app hands over a GPS fix and gets back the city to shop in. Resolved
     * from the nearest open salon rather than a boundary line, because a
     * customer in Thane whose closest salons are all in Mumbai wants Mumbai,
     * and no administrative border is going to tell you that.
     *
     * Always answers. Out of range returns the busiest market with
     * `out_of_range`, so the app can say "we are not near you yet" and still
     * show something rather than a blank screen.
     */
    public function nearest(Request $request, GeoService $geo)
    {
        $request->validate([
            'lat' => 'required|numeric|between:-90,90',
            'lng' => 'required|numeric|between:-180,180',
        ]);

        if (! $geo->isValid($request->lat, $request->lng)) {
            return response()->json([
                'success' => false,
                'message' => 'That does not look like a real location.',
            ], 422);
        }

        $match = $geo->marketFor((float) $request->lat, (float) $request->lng);

        $city = $match['city'] ?? City::where('is_active', true)
            ->serviceable()
            ->withOpenSalonCount()
            ->orderByDesc('salon_count')
            ->first();

        if (! $city) {
            return response()->json([
                'success' => false,
                'message' => 'No cities are live yet.',
            ], 404);
        }

        return response()->json([
            'success' => true,
            'source' => $match['source'],
            'distance_km' => $match['distance_km'],
            'in_range' => $match['source'] !== 'out_of_range',
            'city' => City::where('id', $city->id)->withOpenSalonCount()->first(),
        ]);
    }
}
