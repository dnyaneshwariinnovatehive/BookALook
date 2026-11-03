<?php

namespace App\Support;

use App\Models\AppRelease;
use App\Models\AppUpdatePolicy;
use App\Models\Banner;
use App\Models\City;
use App\Models\NotificationTemplate;
use App\Models\PlatformPolicySetting;
use App\Models\Review;
use App\Models\Salon;
use App\Models\SalonMedia;
use App\Models\ServiceCategory;
use App\Models\SubArea;
use App\Models\SubscriptionPlan;
use Illuminate\Database\Eloquent\Model;

/**
 * Drops cached reads when the rows behind them change.
 *
 * Hooked to model events (created, updated, deleted, restored), so it does
 * not matter which controller, command or service made the change. AppCache
 * defers the drop until the transaction commits. Bulk query-builder writes
 * fire no model events; the few that touch cached data call CacheKeys
 * directly (SalonMedia replacement in onboarding and registration).
 */
final class AppCacheInvalidation
{
    public static function register(): void
    {
        self::on(AppUpdatePolicy::class, fn (Model $m) => CacheKeys::forgetAppVersion((string) $m->app));
        self::on(AppRelease::class, fn (Model $m) => CacheKeys::forgetAppVersion((string) $m->app));

        self::on(ServiceCategory::class, fn () => AppCache::forget(CacheKeys::categories()));

        self::on(City::class, function (Model $m) {
            CacheKeys::forgetCities();
            CacheKeys::forgetSubAreas($m->getKey());
        });
        self::on(SubArea::class, fn (Model $m) => CacheKeys::forgetSubAreas($m->city_id));

        // A salon opening, closing or moving changes the counts and the
        // "serviceable" lists; its name and cover feed the gallery fallback.
        self::on(Salon::class, function (Model $m) {
            CacheKeys::forgetCities();
            CacheKeys::forgetSubAreas($m->city_id);
            if ($m->wasChanged('city_id') && $m->getOriginal('city_id')) {
                CacheKeys::forgetSubAreas($m->getOriginal('city_id'));
            }
            CacheKeys::forgetSalonProfile($m->getKey());
        });
        self::on(SalonMedia::class, fn (Model $m) => AppCache::forget(CacheKeys::salonGallery($m->salon_id)));
        self::on(Review::class, fn (Model $m) => AppCache::forget(CacheKeys::salonRatings($m->salon_id)));

        self::on(SubscriptionPlan::class, fn () => AppCache::forget(CacheKeys::plans()));
        self::on(PlatformPolicySetting::class, fn () => AppCache::forget(CacheKeys::settings()));
        self::on(Banner::class, fn (Model $m) => AppCache::forget(CacheKeys::bannerResolution($m->getKey())));
        self::on(NotificationTemplate::class, function (Model $m) {
            AppCache::forget(CacheKeys::template((string) $m->key));
            if ($m->getOriginal('key') && $m->getOriginal('key') !== $m->key) {
                AppCache::forget(CacheKeys::template((string) $m->getOriginal('key')));
            }
        });
    }

    /** @param class-string<Model> $model */
    private static function on(string $model, \Closure $forget): void
    {
        $model::saved($forget);
        $model::deleted($forget);
        if (method_exists($model, 'restored')) {
            $model::restored($forget);
        }
    }
}
