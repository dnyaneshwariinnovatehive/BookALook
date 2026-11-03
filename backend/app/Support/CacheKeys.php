<?php

namespace App\Support;

/**
 * Every key AppCache uses, in one place, with its TTL.
 *
 * Final Redis key = "bookalook:{APP_ENV}:" (connection prefix) + the key here,
 * e.g. bookalook:production:locations:cities:serviceable.
 *
 * What is NOT here, on purpose: slot availability, bookability, prices a
 * customer pays, first-time offers, favourites, discovery results, wallet,
 * payments, payouts, commission and any setting that decides money or who
 * may book. Those are always read from PostgreSQL.
 */
final class CacheKeys
{
    public const TTL_APP_VERSION = 300;      // 5 min
    public const TTL_CATEGORIES = 1800;      // 30 min
    public const TTL_LOCATIONS = 600;        // 10 min: includes open-salon counts
    public const TTL_PLANS = 900;            // 15 min
    public const TTL_SETTINGS = 300;         // 5 min
    public const TTL_SALON_PROFILE = 300;    // 5 min
    public const TTL_BANNER_RESOLUTION = 900; // 15 min (unchanged)
    public const TTL_TEMPLATE = 900;         // 15 min (was 24 h)
    public const TTL_FCM_TOKEN = 3000;       // 50 min; Google's token lasts 60

    /** $view: "enforcement" (middleware) or "public" (GET /app-version). */
    public static function appVersion(string $app, string $view): string
    {
        return "app:version:{$app}:{$view}";
    }

    public static function categories(): string
    {
        return 'categories:active';
    }

    public static function cities(bool $serviceable): string
    {
        return 'locations:cities:' . ($serviceable ? 'serviceable' : 'all');
    }

    public static function subAreas(string $cityId, bool $serviceable): string
    {
        return "locations:subareas:{$cityId}:" . ($serviceable ? 'serviceable' : 'all');
    }

    public static function plans(): string
    {
        return 'plans:active';
    }

    public static function settings(): string
    {
        return 'settings:public';
    }

    public static function salonGallery(string $salonId): string
    {
        return "salon:profile:{$salonId}:gallery";
    }

    public static function salonRatings(string $salonId): string
    {
        return "salon:profile:{$salonId}:ratings";
    }

    public static function bannerResolution(string $bannerId): string
    {
        return "banners:resolution:{$bannerId}";
    }

    public static function template(string $key): string
    {
        return "notifications:template:{$key}";
    }

    public static function fcmToken(): string
    {
        return 'push:fcm:access-token';
    }

    // --- Invalidation helpers (called from model events, after commit) ----

    public static function forgetAppVersion(string $app): void
    {
        AppCache::forget(self::appVersion($app, 'enforcement'), self::appVersion($app, 'public'));
    }

    public static function forgetCities(): void
    {
        AppCache::forget(self::cities(true), self::cities(false));
    }

    public static function forgetSubAreas(?string $cityId): void
    {
        if ($cityId) {
            AppCache::forget(self::subAreas($cityId, true), self::subAreas($cityId, false));
        }
    }

    public static function forgetSalonProfile(string $salonId): void
    {
        AppCache::forget(self::salonGallery($salonId), self::salonRatings($salonId));
    }
}
