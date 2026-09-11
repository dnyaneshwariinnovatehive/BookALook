<?php

namespace App\Services;

use App\Models\City;
use App\Models\Salon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

/**
 * Where things are, and how far apart.
 *
 * One place owns this because the answer has to be the same everywhere: the
 * distance shown on a salon card and the order that card appears in are the
 * same number, and computing it twice is how they end up disagreeing.
 *
 * Distances are straight-line, not driving distance. That is honest for
 * ordering a list — the nearest salon as the crow flies is almost always the
 * nearest to walk to as well — and it needs no third-party routing bill.
 */
class GeoService
{
    /** Mean radius of the Earth, in kilometres. */
    private const EARTH_RADIUS_KM = 6371;

    /**
     * How far out to keep looking when deciding which market a coordinate is
     * in. Beyond this the customer is not near any salon the platform has, and
     * guessing a city for them is worse than admitting it.
     */
    public const NEAREST_CITY_LIMIT_KM = 150;

    public function isValid(mixed $lat, mixed $lng): bool
    {
        if (! is_numeric($lat) || ! is_numeric($lng)) {
            return false;
        }

        $lat = (float) $lat;
        $lng = (float) $lng;

        // 0,0 is in the Gulf of Guinea and is what a broken GPS reading looks
        // like, so it is treated as no reading at all.
        return $lat >= -90 && $lat <= 90
            && $lng >= -180 && $lng <= 180
            && ! ($lat === 0.0 && $lng === 0.0);
    }

    /** Straight-line kilometres between two points. */
    public function distanceKm(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);

        $a = sin($dLat / 2) ** 2
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;

        return round(self::EARTH_RADIUS_KM * 2 * asin(min(1.0, sqrt($a))), 2);
    }

    /**
     * The SQL that measures from a salon row to a point, per driver.
     *
     * SQLite ships without trigonometry, so AppServiceProvider registers a
     * `haversine_km` function on the connection. MySQL and Postgres have the
     * maths already and get the formula inline. Either way the caller writes
     * one query.
     *
     * @return array{0: string, 1: array<int, float>}
     */
    private function distanceSql(float $lat, float $lng): array
    {
        $driver = DB::connection()->getDriverName();

        if ($driver === 'sqlite') {
            return ['haversine_km(salons.latitude, salons.longitude, ?, ?)', [$lat, $lng]];
        }

        // Clamped before acos: floating point can nudge the dot product a hair
        // past 1 for two points in the same place, and acos(1.0000001) is NaN.
        $sql = '(' . self::EARTH_RADIUS_KM . ' * acos(LEAST(1.0, GREATEST(-1.0,
            cos(radians(?)) * cos(radians(salons.latitude))
            * cos(radians(salons.longitude) - radians(?))
            + sin(radians(?)) * sin(radians(salons.latitude))
        ))))';

        return [$sql, [$lat, $lng, $lat]];
    }

    /**
     * Add a `distance_km` column and order by it.
     *
     * Written as SQL rather than sorted in PHP so paging and limits stay
     * correct — sorting a page of results only sorts that page.
     *
     * Salons with no coordinates sort last rather than disappearing: a salon
     * that has not pinned itself is still open for business.
     */
    public function orderByDistance(Builder $query, float $lat, float $lng): Builder
    {
        [$distance, $bindings] = $this->distanceSql($lat, $lng);

        return $query
            ->select('salons.*')
            ->selectRaw("{$distance} AS distance_km", $bindings)
            ->orderByRaw('CASE WHEN salons.latitude IS NULL OR salons.longitude IS NULL THEN 1 ELSE 0 END')
            ->orderByRaw("{$distance} ASC", $bindings)
            // Salons that have not pinned themselves all sit on their city
            // centre and therefore tie exactly. Rating breaks the tie, so the
            // order is still useful instead of arbitrary.
            ->orderByDesc('salons.avg_rating')
            ->orderBy('salons.name');
    }

    /**
     * Which market a coordinate belongs to.
     *
     * The nearest open salon decides it, not the nearest city centre. That
     * handles the cases a boundary cannot: someone in Thane whose closest
     * salons are all in Mumbai should be shown Mumbai, and a city the platform
     * has written down but does not trade in should never be the answer.
     *
     * @return array{city: ?City, distance_km: ?float, source: string}
     */
    public function marketFor(float $lat, float $lng): array
    {
        $nearestSalon = Salon::query()
            ->where('status', 'active')
            ->whereNotNull('latitude')
            ->whereNotNull('longitude')
            ->whereNotNull('city_id')
            ->get(['id', 'city_id', 'latitude', 'longitude'])
            ->map(fn (Salon $salon) => [
                'salon' => $salon,
                'km' => $this->distanceKm($lat, $lng, (float) $salon->latitude, (float) $salon->longitude),
            ])
            ->sortBy('km')
            ->first();

        if ($nearestSalon && $nearestSalon['km'] <= self::NEAREST_CITY_LIMIT_KM) {
            return [
                'city' => City::find($nearestSalon['salon']->city_id),
                'distance_km' => $nearestSalon['km'],
                'source' => 'nearest_salon',
            ];
        }

        // No salon near enough. Fall back to the nearest city the platform
        // actually serves, so a customer just outside a market still lands in
        // the one next to them rather than nowhere.
        $nearestCity = City::query()
            ->serviceable()
            ->whereNotNull('latitude')
            ->whereNotNull('longitude')
            ->get()
            ->map(fn (City $city) => [
                'city' => $city,
                'km' => $this->distanceKm($lat, $lng, (float) $city->latitude, (float) $city->longitude),
            ])
            ->sortBy('km')
            ->first();

        if ($nearestCity && $nearestCity['km'] <= self::NEAREST_CITY_LIMIT_KM) {
            return [
                'city' => $nearestCity['city'],
                'distance_km' => $nearestCity['km'],
                'source' => 'nearest_city',
            ];
        }

        return ['city' => null, 'distance_km' => null, 'source' => 'out_of_range'];
    }
}
