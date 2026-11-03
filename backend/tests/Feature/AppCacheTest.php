<?php

namespace {
    // PhpRedis is not installed where these tests run; the class is only
    // needed so a test store can throw what PhpRedis throws on an outage.
    if (! class_exists('RedisException')) {
        class RedisException extends \RuntimeException
        {
        }
    }
}

namespace Tests\Feature {

use App\Models\Appointment;
use App\Models\AppUpdatePolicy;
use App\Models\PlatformPolicySetting;
use App\Models\Review;
use App\Models\Salon;
use App\Models\SalonMedia;
use App\Models\SalonWorkingHour;
use App\Models\ServiceCategory;
use App\Models\User;
use App\Support\AppCache;
use App\Support\CacheKeys;
use Illuminate\Contracts\Cache\Store;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Phase 3 caching: hits, invalidation (create/update/delete, after commit
 * only), outage fallback to PostgreSQL, and what must never be cached.
 */
class AppCacheTest extends TestCase
{
    use DatabaseTransactions;

    private string $unique;

    protected function setUp(): void
    {
        parent::setUp();
        $this->unique = substr(bin2hex(random_bytes(6)), 0, 8);
        Cache::flush();
    }

    private function queries(callable $run): int
    {
        DB::flushQueryLog();
        DB::enableQueryLog();
        $run();
        $count = count(DB::getQueryLog());
        DB::disableQueryLog();

        return $count;
    }

    private function category(string $name, int $order = 1): ServiceCategory
    {
        return ServiceCategory::create(['name' => "{$name} {$this->unique}", 'is_active' => true, 'is_custom' => false, 'display_order' => $order]);
    }

    private function salon(): Salon
    {
        $admin = User::create([
            'id' => (string) Str::uuid(), 'role' => 'admin', 'name' => "Owner {$this->unique}",
            'phone' => '8'.substr(str_pad((string) crc32($this->unique), 9, '0'), 0, 9), 'password_hash' => 'x', 'is_active' => true,
        ]);

        return Salon::create([
            'id' => (string) Str::uuid(), 'admin_id' => $admin->id, 'name' => "Salon {$this->unique}",
            'slug' => "salon-{$this->unique}", 'address' => '1 Street', 'submitted_by' => $admin->id, 'status' => 'active',
        ]);
    }

    /** Makes the default (or given) store behave like an unreachable Redis. */
    private function breakCache(string $store = 'array'): void
    {
        Cache::extend('broken', fn () => Cache::repository(new BrokenStore));
        config(["cache.stores.{$store}" => ['driver' => 'broken']]);
        Cache::forgetDriver($store);
    }

    // --- Hits -----------------------------------------------------------------

    public function test_categories_are_read_from_the_database_once_then_from_the_cache(): void
    {
        $this->category('Hair');

        $first = $this->queries(fn () => $this->getJson('/api/customer/categories')->assertOk());
        $second = $this->queries(fn () => $this->getJson('/api/customer/categories')->assertOk());

        $this->assertLessThan($first, $second, "first {$first} queries, second {$second}");
    }

    public function test_icon_urls_are_still_built_for_the_requesting_host(): void
    {
        ServiceCategory::create(['name' => "Icon {$this->unique}", 'icon_url' => 'category-icons/a.png', 'is_active' => true, 'is_custom' => false, 'display_order' => 1]);

        $a = $this->getJson('http://one.test/api/customer/categories')->json('categories');
        $b = $this->getJson('http://two.test/api/customer/categories')->json('categories');

        $mine = fn ($list) => collect($list)->firstWhere('name', "Icon {$this->unique}")['icon_url'] ?? '';
        $this->assertStringNotContainsString('one.test', $mine($b));
    }

    // --- Invalidation -------------------------------------------------------------

    public function test_a_new_changed_or_deleted_category_shows_at_once(): void
    {
        $this->getJson('/api/customer/categories')->assertOk();

        $cat = $this->category('Fresh');
        $names = fn () => collect($this->getJson('/api/customer/categories')->json('categories'))->pluck('name');
        $this->assertContains("Fresh {$this->unique}", $names());

        $cat->update(['name' => "Renamed {$this->unique}"]);
        $this->assertContains("Renamed {$this->unique}", $names());

        $cat->delete();
        $this->assertNotContains("Renamed {$this->unique}", $names());
    }

    public function test_invalidation_waits_for_the_transaction_to_commit(): void
    {
        $cat = $this->category('Tx');
        $this->getJson('/api/customer/categories')->assertOk();
        $this->assertNotNull(Cache::get(CacheKeys::categories()));

        DB::beginTransaction();
        $cat->update(['name' => "Changed {$this->unique}"]);
        // Not committed yet: the cached list must not be dropped, and a read
        // inside the transaction must not cache uncommitted rows.
        $this->assertNotNull(Cache::get(CacheKeys::categories()));
        DB::commit();

        $this->assertNull(Cache::get(CacheKeys::categories()));
    }

    public function test_a_read_inside_a_rolled_back_transaction_is_never_cached(): void
    {
        DB::beginTransaction();
        $this->assertSame('uncommitted', AppCache::remember('test:in-tx', 60, fn () => 'uncommitted'));
        $this->assertNull(Cache::get('test:in-tx'), 'not written before the commit');
        DB::rollBack();

        $this->assertNull(Cache::get('test:in-tx'));
    }

    public function test_a_read_inside_a_committed_transaction_is_cached_after_the_commit(): void
    {
        DB::beginTransaction();
        AppCache::remember('test:committed', 60, fn () => 'committed');
        DB::commit();

        $this->assertNotNull(Cache::get('test:committed'));
    }

    public function test_plans_are_cached_and_refreshed_when_a_plan_changes(): void
    {
        $plan = \App\Models\SubscriptionPlan::create(['id' => (string) Str::uuid(), 'name' => "Plan {$this->unique}", 'price' => 499, 'duration_days' => 30, 'is_active' => true]);
        $this->getJson('/api/public/subscription-plans')->assertOk();
        $this->assertNotNull(Cache::get(CacheKeys::plans()));

        $plan->update(['price' => 599]);
        $this->assertNull(Cache::get(CacheKeys::plans()));
    }

    public function test_app_version_caches_are_separate_and_both_dropped_on_change(): void
    {
        $this->getJson('/api/app-version/customer')->assertOk();
        $this->getJson('/api/customer/categories', ['X-App-Id' => 'customer', 'X-App-Version' => '1.0.0', 'X-App-Build' => '1'])->assertOk();

        $public = Cache::get(CacheKeys::appVersion('customer', 'public'));
        $enforcement = Cache::get(CacheKeys::appVersion('customer', 'enforcement'));
        $this->assertNotNull($public);
        $this->assertNotNull($enforcement);
        $this->assertNotEquals($public, $enforcement, 'the two shapes no longer share one key');

        AppUpdatePolicy::create(['app' => 'customer', 'update_mode' => 'optional', 'is_enforced' => false]);
        $this->assertNull(Cache::get(CacheKeys::appVersion('customer', 'public')));
        $this->assertNull(Cache::get(CacheKeys::appVersion('customer', 'enforcement')));
    }

    public function test_cached_settings_follow_updates_and_money_settings_are_never_cached(): void
    {
        PlatformPolicySetting::updateOrCreate(['setting_key' => 'android_app_url'], ['setting_value' => 'https://a.test', 'data_type' => 'string']);
        $this->assertSame('https://a.test', PlatformPolicySetting::cachedValue('android_app_url'));

        PlatformPolicySetting::updateOrCreate(['setting_key' => 'android_app_url'], ['setting_value' => 'https://b.test', 'data_type' => 'string']);
        $this->assertSame('https://b.test', PlatformPolicySetting::cachedValue('android_app_url'));

        foreach (['coin_value_inr', 'commission_dues_min_amount', 'first_time_discount_platform_max_cap', 'payment_upi_id', 'cancellation_cutoff_minutes', 'customer_cancellation_limit'] as $key) {
            try {
                PlatformPolicySetting::cachedValue($key);
                $this->fail("{$key} must not be readable through the cache");
            } catch (\LogicException) {
                $this->addToAssertionCount(1);
            }
        }
    }

    public function test_salon_gallery_and_ratings_are_cached_and_dropped_on_change(): void
    {
        $salon = $this->salon();
        $this->getJson("/api/customer/salons/{$salon->id}")->assertOk();
        $this->assertNotNull(Cache::get(CacheKeys::salonGallery($salon->id)));
        $this->assertNotNull(Cache::get(CacheKeys::salonRatings($salon->id)));

        SalonMedia::create(['id' => (string) Str::uuid(), 'salon_id' => $salon->id, 'media_type' => 'image', 'file_url' => 'https://img.test/1.jpg', 'sort_order' => 1, 'uploaded_by' => $salon->admin_id]);
        $this->assertNull(Cache::get(CacheKeys::salonGallery($salon->id)));
        $this->assertSame('https://img.test/1.jpg', $this->getJson("/api/customer/salons/{$salon->id}")->json('salon.gallery.0.url'));

        // A review change drops the ratings (event fired directly: a review
        // needs a completed appointment, which is beside the point here).
        event('eloquent.saved: ' . Review::class, new Review(['salon_id' => $salon->id]));
        $this->assertNull(Cache::get(CacheKeys::salonRatings($salon->id)));
    }

    // --- Must stay fresh ------------------------------------------------------------

    public function test_salon_row_hours_and_bookability_are_never_served_from_the_cache(): void
    {
        $salon = $this->salon();
        $this->getJson("/api/customer/salons/{$salon->id}")->assertOk();

        // Changed without any model event, so no invalidation can help:
        DB::table('salons')->where('id', $salon->id)->update(['name' => "Live {$this->unique}", 'advance_required' => true]);
        $today = now()->dayOfWeek;
        DB::table('salon_working_hours')->insert([
            'id' => (string) Str::uuid(), 'salon_id' => $salon->id, 'day_of_week' => $today,
            'is_closed' => true, 'open_time' => '09:00:00', 'close_time' => '10:00:00',
        ]);

        $res = $this->getJson("/api/customer/salons/{$salon->id}")->assertOk();
        $this->assertSame("Live {$this->unique}", $res->json('salon.name'));
        $this->assertTrue($res->json('salon.advance_required'));
        $this->assertNotNull($res->json('salon.is_bookable'));
        $this->assertNull(Cache::get('salon:profile:' . $salon->id), 'no whole-salon cache entry exists');
    }

    // --- Outage ------------------------------------------------------------------

    public function test_with_the_cache_down_public_reads_come_from_the_database(): void
    {
        $this->category('Outage');
        $this->breakCache();

        $names = collect($this->getJson('/api/customer/categories')->assertOk()->json('categories'))->pluck('name');
        $this->assertContains("Outage {$this->unique}", $names);

        $this->getJson('/api/app-version/customer')->assertOk();
        $this->getJson('/api/cities')->assertOk();
    }

    public function test_with_the_cache_down_a_booking_change_is_not_blocked_by_the_sync_debounce(): void
    {
        $this->breakCache();
        $appointment = new Appointment(['salon_id' => (string) Str::uuid()]);

        $nudge = new \ReflectionMethod(Appointment::class, 'nudgeSalon');
        $nudge->invoke($appointment); // must not throw

        $this->addToAssertionCount(1);
    }

    public function test_with_the_cache_down_an_update_still_succeeds_and_the_failure_is_logged(): void
    {
        $cat = $this->category('Logged');
        $this->breakCache();
        \Illuminate\Support\Facades\Log::spy();

        $cat->update(['name' => "Still saved {$this->unique}"]);

        $this->assertSame("Still saved {$this->unique}", $cat->fresh()->name);
        \Illuminate\Support\Facades\Log::shouldHaveReceived('log')->withArgs(fn ($level, $event) => $level === 'error' && $event === 'app_cache.invalidate_failed');
    }

    public function test_with_the_state_store_down_sign_in_fails_closed(): void
    {
        $this->breakCache('state');
        $this->withoutExceptionHandling();

        $this->expectException(\RedisException::class);
        $this->postJson('/api/customer/auth/verify-otp', ['phone' => '9000000001', 'otp' => '123456']);
    }
}

/** A cache store whose every call fails like an unreachable Redis. */
class BrokenStore implements Store, \Illuminate\Contracts\Cache\LockProvider
{
    public function lock($name, $seconds = 0, $owner = null) { $this->down(); }
    public function restoreLock($name, $owner) { $this->down(); }

    private function down(): never
    {
        throw new \RedisException('Connection refused');
    }

    public function get($key) { $this->down(); }
    public function many(array $keys) { $this->down(); }
    public function put($key, $value, $seconds) { $this->down(); }
    public function putMany(array $values, $seconds) { $this->down(); }
    public function increment($key, $value = 1) { $this->down(); }
    public function decrement($key, $value = 1) { $this->down(); }
    public function forever($key, $value) { $this->down(); }
    public function forget($key) { $this->down(); }
    public function flush() { $this->down(); }
    public function getPrefix() { return ''; }
    public function add($key, $value, $seconds) { $this->down(); }
}

}
