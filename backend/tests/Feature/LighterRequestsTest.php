<?php

namespace Tests\Feature;

use App\Models\City;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Services\SalonAccessService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Laravel\Sanctum\PersonalAccessToken;
use Tests\TestCase;

/**
 * Browsing is read-only, the salon list costs the same number of queries
 * however many salons a city has, and a signed-in request does not write its
 * token on every call — without changing who can be booked.
 */
class LighterRequestsTest extends TestCase
{
    use DatabaseTransactions;

    private string $u;

    private City $city;

    private SubscriptionPlan $plan;

    protected function setUp(): void
    {
        parent::setUp();
        Cache::flush();
        $this->u = substr(bin2hex(random_bytes(6)), 0, 8);
        $this->city = City::create(['id' => (string) Str::uuid(), 'name' => "Light {$this->u}", 'state' => 'MH', 'is_active' => true]);
        $this->plan = SubscriptionPlan::first() ?? SubscriptionPlan::create(['id' => (string) Str::uuid(), 'name' => 'P', 'price' => 999, 'duration_days' => 30, 'is_active' => true]);
    }

    private function salon(?string $endDate = '+20 days', string $status = 'active'): Salon
    {
        $owner = User::create(['id' => (string) Str::uuid(), 'role' => 'admin', 'name' => 'O', 'phone' => '7'.random_int(100000000, 999999999), 'password_hash' => 'x', 'is_active' => true]);
        $salon = Salon::create(['id' => (string) Str::uuid(), 'admin_id' => $owner->id, 'name' => 'S '.Str::random(5), 'slug' => 's-'.Str::lower(Str::random(10)), 'address' => 'x', 'submitted_by' => $owner->id, 'status' => 'active', 'city_id' => $this->city->id]);
        SalonSubscription::create([
            'id' => (string) Str::uuid(), 'salon_id' => $salon->id, 'plan_id' => $this->plan->id,
            'billing_type' => \App\Support\BillingModel::SUBSCRIPTION, 'plan_price_snapshot' => 999,
            'start_date' => Carbon::today()->subDays(40), 'status' => $status,
            'end_date' => $endDate === null ? null : Carbon::parse($endDate)->toDateString(),
        ]);

        return $salon;
    }

    /** @return array{0:int,1:array<int,string>} query count and the write statements */
    private function measure(string $url): array
    {
        DB::flushQueryLog();
        DB::enableQueryLog();
        $this->getJson($url)->assertOk();
        $log = DB::getQueryLog();
        DB::disableQueryLog();

        $writes = array_values(array_filter(array_column($log, 'query'), fn ($q) => preg_match('/^\s*(update|insert|delete)/i', $q)));

        return [count($log), $writes];
    }

    public function test_browsing_the_salon_list_and_a_salon_page_never_writes(): void
    {
        $salon = $this->salon();
        $this->salon('-3 days'); // a lapsed plan still marked active

        [, $listWrites] = $this->measure("/api/customer/salons?city_id={$this->city->id}");
        [, $pageWrites] = $this->measure("/api/customer/salons/{$salon->id}");

        $this->assertSame([], $listWrites);
        $this->assertSame([], $pageWrites);
    }

    public function test_the_salon_list_costs_the_same_queries_for_3_or_15_salons(): void
    {
        foreach (range(1, 3) as $_) {
            $this->salon();
        }
        $this->getJson("/api/customer/salons?city_id={$this->city->id}"); // warm caches
        [$few] = $this->measure("/api/customer/salons?city_id={$this->city->id}");

        foreach (range(1, 12) as $_) {
            $this->salon();
        }
        [$many] = $this->measure("/api/customer/salons?city_id={$this->city->id}");

        $this->assertSame($few, $many, "{$few} queries for 3 salons, {$many} for 15");
    }

    public function test_a_plan_past_its_end_date_is_lapsed_without_being_written(): void
    {
        $salon = $this->salon('-1 day');

        $status = app(SalonAccessService::class)->status($salon->fresh());

        $this->assertFalse($status['is_active']);
        $this->assertSame(SalonAccessService::REASON_SUBSCRIPTION_EXPIRED, $status['reason']);
        $this->assertSame('active', SalonSubscription::where('salon_id', $salon->id)->value('status'), 'the hourly job marks it, not a read');

        $listed = collect($this->getJson("/api/customer/salons?city_id={$this->city->id}")->json('salons'))->firstWhere('id', $salon->id);
        $this->assertNotNull($listed);
        $this->assertFalse((bool) $listed['is_serviceable'], 'a lapsed salon cannot be booked');
    }

    public function test_a_plan_ending_today_still_runs_today(): void
    {
        $salon = $this->salon('today');

        $this->assertTrue(app(SalonAccessService::class)->status($salon->fresh())['is_active']);
    }

    public function test_the_hourly_job_still_marks_lapsed_plans_expired(): void
    {
        $salon = $this->salon('-2 days');

        app(SalonAccessService::class)->expireStale();

        $this->assertSame('expired', SalonSubscription::where('salon_id', $salon->id)->value('status'));
    }

    public function test_a_token_is_stamped_at_most_every_ten_minutes(): void
    {
        $user = User::create(['id' => (string) Str::uuid(), 'role' => 'customer', 'name' => 'C', 'phone' => '7'.random_int(100000000, 999999999), 'password_hash' => 'x', 'is_active' => true]);
        $token = $user->createToken('customer_app')->plainTextToken;
        $id = PersonalAccessToken::findToken($token)->id;
        $stamp = fn () => DB::table('personal_access_tokens')->where('id', $id)->value('last_used_at');
        $call = function () use ($token) {
            $this->app['auth']->forgetGuards();
            $this->withToken($token)->getJson('/api/customer/profile')->assertSuccessful();
        };

        $call();
        $first = $stamp();
        $this->assertNotNull($first, 'the first use is recorded');

        $this->travel(3)->minutes();
        $call();
        $this->assertSame($first, $stamp(), 'three minutes later: no write');

        $this->travel(11)->minutes();
        $call();
        $this->assertNotSame($first, $stamp(), 'after ten minutes it is stamped again');
    }

    public function test_the_app_uses_the_throttled_token_model(): void
    {
        $this->assertSame(\App\Models\PersonalAccessToken::class, \Laravel\Sanctum\Sanctum::$personalAccessTokenModel);
    }
}
