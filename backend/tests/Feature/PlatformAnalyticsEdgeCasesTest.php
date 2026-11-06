<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\Salon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\TestDox;
use Tests\Support\AnalyticsFixtures;
use Tests\TestCase;

/**
 * Edge cases for the money-in-pocket card and the analytics dashboard: odd
 * money states, odd date ranges, empty or unknown filters, bookings that are
 * not really bookings, totals that must agree with each other, and access.
 */
class PlatformAnalyticsEdgeCasesTest extends TestCase
{
    use DatabaseTransactions;
    use AnalyticsFixtures;

    private const SECTIONS = ['overview', 'money', 'bookings', 'places', 'salons', 'catalog', 'customers', 'engagement'];

    protected function setUp(): void
    {
        parent::setUp();
        $this->setUpAnalyticsFixtures();
    }

    /** Change in one line of the cash position between two snapshots. */
    private function delta(array $before, array $after, string $group, string $key): float
    {
        return round($this->line($after, $group, $key) - $this->line($before, $group, $key), 2);
    }

    private function service(Salon $salon, string $name, string $category, float $price, int $minutes = 30): string
    {
        $cat = (string) Str::uuid();
        DB::table('service_categories')->insert(['id' => $cat, 'name' => "{$category} {$this->tag}", 'is_custom' => false, 'is_active' => true, 'display_order' => 0]);
        $tpl = (string) Str::uuid();
        DB::table('service_templates')->insert(['id' => $tpl, 'category_id' => $cat, 'name' => "{$name} {$this->tag}", 'estimated_duration_minutes' => $minutes, 'is_custom' => false, 'is_active' => true]);
        $svc = (string) Str::uuid();
        DB::table('services')->insert(['id' => $svc, 'salon_id' => $salon->id, 'template_id' => $tpl, 'price' => $price, 'is_active' => true, 'display_order' => 0, 'created_at' => now(), 'updated_at' => now()]);

        return $svc;
    }

    private function serviceLine(Appointment $a, string $serviceId, float $price, int $minutes, ?string $providerId = null, ?float $original = null): void
    {
        DB::table('appointment_services')->insert([
            'id' => (string) Str::uuid(), 'appointment_id' => $a->id, 'service_id' => $serviceId, 'serving_provider_id' => $providerId,
            'price_at_booking' => $price, 'original_service_price' => $original ?? $price, 'duration_minutes_at_booking' => $minutes,
            'line_status' => $a->status === 'completed' ? 'completed' : 'booked', 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    // ================================================================ money in pocket

    #[TestDox('Money in pocket: the breakdown always adds up (in pocket = cash held − still owed)')]
    public function test_cash_position_lines_always_add_up(): void
    {
        $c = $this->cash();
        $sum = fn (string $g) => array_sum(array_column($c[$g], 'amount'));

        $this->assertEquals(round($sum('cash_in') - $sum('cash_out'), 2), $c['cash_held']);
        $this->assertEquals(round($sum('owed_out'), 2), $c['still_owed']);
        $this->assertEquals(round($c['cash_held'] - $c['still_owed'], 2), $c['in_pocket']);
        $this->assertSame(['online_collected', 'plan_payments', 'dues_collected'], array_column($c['cash_in'], 'key'));
        $this->assertSame(['paid_to_salons', 'refunds_paid', 'gateway_fee'], array_column($c['cash_out'], 'key'));
        $this->assertSame(['open_payouts', 'unsettled_advances', 'refunds_queued'], array_column($c['owed_out'], 'key'));
    }

    #[TestDox('Money in pocket: cash and UPI taken at the salon counter is never counted')]
    public function test_counter_payments_are_ignored(): void
    {
        $before = $this->cash();
        $a = $this->booking($this->salon('Counter'), '2026-10-10', 'completed', 1500);
        $this->pay($a, 1500, null, type: 'balance');

        $after = $this->cash();
        $this->assertEquals($before['in_pocket'], $after['in_pocket']);
        $this->assertEquals($before['cash_held'], $after['cash_held']);
    }

    #[TestDox('Money in pocket: failed or abandoned gateway payments are never counted')]
    public function test_unsuccessful_payments_are_ignored(): void
    {
        $before = $this->cash();
        $a = $this->booking($this->salon('Failed'), '2026-11-10', 'scheduled', 800);
        $this->pay($a, 400, 'razorpay', status: 'failed');
        $this->pay($a, 400, 'razorpay', status: 'created');

        $this->assertEquals(0, $this->delta($before, $this->cash(), 'cash_in', 'online_collected'));
    }

    #[TestDox('Money in pocket: an upcoming booking\'s advance is held for the salon, not kept')]
    public function test_upcoming_advance_is_owed_not_kept(): void
    {
        $before = $this->cash();
        $a = $this->booking($this->salon('Upcoming'), '2026-11-20', 'scheduled', 1000);
        $this->pay($a, 250, 'demo');
        $after = $this->cash();

        $this->assertEquals(250, round($after['cash_held'] - $before['cash_held'], 2));
        $this->assertEquals(250, $this->delta($before, $after, 'owed_out', 'unsettled_advances'));
        $this->assertEquals($before['in_pocket'], $after['in_pocket']);
    }

    #[TestDox('Money in pocket: a partial refund on an unsettled booking leaves only the remainder owed')]
    public function test_partial_refund_leaves_the_remainder_owed(): void
    {
        $before = $this->cash();
        $a = $this->booking($this->salon('Partial'), '2026-11-02', 'cancelled', 1000);
        $this->refund($a, $this->pay($a, 400, 'demo'), 150, 'processed');
        $after = $this->cash();

        $this->assertEquals(150, $this->delta($before, $after, 'cash_out', 'refunds_paid'));
        $this->assertEquals(250, $this->delta($before, $after, 'owed_out', 'unsettled_advances'));
        $this->assertEquals($before['in_pocket'], $after['in_pocket']);
    }

    #[TestDox('Money in pocket: failed refunds never left, so they are not counted anywhere')]
    public function test_failed_refunds_are_ignored(): void
    {
        $a = $this->booking($this->salon('Refund fail'), '2026-11-02', 'cancelled', 600);
        $payment = $this->pay($a, 300, 'demo');
        $before = $this->cash();
        $this->refund($a, $payment, 300, 'failed');
        $after = $this->cash();

        $this->assertEquals(0, $this->delta($before, $after, 'cash_out', 'refunds_paid'));
        $this->assertEquals(0, $this->delta($before, $after, 'owed_out', 'refunds_queued'));
        $this->assertEquals(0, $this->delta($before, $after, 'owed_out', 'unsettled_advances'));
    }

    #[TestDox('Money in pocket: pending, processing and awaiting-manual refunds all count as still owed')]
    public function test_every_unfinished_refund_status_is_owed(): void
    {
        $before = $this->cash();
        $salon = $this->salon('Queued');
        foreach (['pending' => 100, 'processing' => 200, 'awaiting_manual' => 300] as $status => $amount) {
            $a = $this->booking($salon, '2026-11-02', 'cancelled', 1000);
            $this->refund($a, $this->pay($a, $amount, 'demo'), $amount, $status);
        }
        $after = $this->cash();

        $this->assertEquals(600, $this->delta($before, $after, 'owed_out', 'refunds_queued'));
        $this->assertEquals(0, $this->delta($before, $after, 'owed_out', 'unsettled_advances'));
        $this->assertEquals($before['in_pocket'], $after['in_pocket']);
    }

    #[TestDox('Money in pocket: a refund on a booking already paid out to the salon comes out of cash held')]
    public function test_late_refund_on_settled_booking(): void
    {
        $salon = $this->salon('Late refund');
        $a = $this->booking($salon, '2026-10-05', 'completed', 1000);
        $payment = $this->pay($a, 500);
        $this->payout($salon, 'distributed', 500, 50, 450, [$a], '2026-09-01');
        $before = $this->cash();
        $this->refund($a, $payment, 200, 'processed');
        $after = $this->cash();

        $this->assertEquals(200, $this->delta($before, $after, 'cash_out', 'refunds_paid'));
        $this->assertEquals(0, $this->delta($before, $after, 'owed_out', 'unsettled_advances'));
        $this->assertEquals(-200, round($after['in_pocket'] - $before['in_pocket'], 2));
    }

    #[TestDox('Money in pocket: pending and approved payouts are owed; once distributed they are paid out')]
    public function test_payout_moves_from_owed_to_paid(): void
    {
        $salon = $this->salon('Payout states');
        $before = $this->cash();
        $pending = $this->payout($salon, 'pending', 300, 0, 300);
        $this->payout($salon, 'approved', 200, 0, 200, [], '2026-09-01');
        $mid = $this->cash();
        $this->assertEquals(500, $this->delta($before, $mid, 'owed_out', 'open_payouts'));

        $pending->forceFill(['status' => 'distributed', 'distributed_at' => now()])->save();
        $after = $this->cash();
        $this->assertEquals(200, $this->delta($before, $after, 'owed_out', 'open_payouts'));
        $this->assertEquals(300, $this->delta($before, $after, 'cash_out', 'paid_to_salons'));
    }

    #[TestDox('Money in pocket: commission a salon still owes is shown but not counted until it pays')]
    public function test_salon_owed_dues_count_only_once_paid(): void
    {
        $before = $this->cash();
        $owed = $this->payout($this->salon('Owes'), 'pending', 0, 400, -400);
        $mid = $this->cash();
        $this->assertEquals(400, $this->delta($before, $mid, 'not_counted', 'dues_receivable'));
        $this->assertEquals($before['in_pocket'], $mid['in_pocket']);

        $owed->forceFill(['status' => 'distributed', 'distributed_at' => now()])->save();
        $after = $this->cash();
        $this->assertEquals(0, $this->delta($before, $after, 'not_counted', 'dues_receivable'));
        $this->assertEquals(400, $this->delta($before, $after, 'cash_in', 'dues_collected'));
        $this->assertEquals(400, round($after['in_pocket'] - $before['in_pocket'], 2));
    }

    #[TestDox('Money in pocket: plan payments count the cash after coins; pending and rejected ones are not counted')]
    public function test_plan_payments_cash_after_coins(): void
    {
        $salon = $this->salon('Plans');
        $before = $this->cash();
        $this->planPayment($salon, 'approved', 899, coins: 100, price: 999);
        $this->planPayment($salon, 'approved', null, coins: 200, price: 1999);   // older request: price − coins
        $this->planPayment($salon, 'rejected', 999);
        $this->planPayment($salon, 'pending', 499);
        $after = $this->cash();

        $this->assertEquals(899 + 1799, $this->delta($before, $after, 'cash_in', 'plan_payments'));
        $this->assertEquals(499, $this->delta($before, $after, 'not_counted', 'plans_pending'));
    }

    #[TestDox('Money in pocket: the Razorpay fee applies only to Razorpay money and follows the configured rate')]
    public function test_gateway_fee_rate_and_scope(): void
    {
        $before = $this->cash();
        $a = $this->booking($this->salon('Fee'), '2026-11-20', 'scheduled', 3000);
        $this->pay($a, 1000, 'razorpay');
        $this->pay($a, 1000, 'demo');
        $this->assertEquals(23.6, $this->delta($before, $this->cash(), 'cash_out', 'gateway_fee'));

        config(['services.payments.razorpay.fee_percent' => 0]);
        $zero = $this->cash();
        $this->assertEquals(0, $this->line($zero, 'cash_out', 'gateway_fee'));
        $this->assertEquals(0.0, (float) $zero['fee_percent']);
    }

    #[TestDox('Money in pocket: can go negative when more was paid out than was held, and says so')]
    public function test_in_pocket_can_be_negative_relative_change(): void
    {
        $before = $this->cash();
        // A payout with no recorded gateway money behind it (older bookings).
        $this->payout($this->salon('Legacy'), 'distributed', 700, 0, 700);
        $after = $this->cash();

        $this->assertEquals(-700, round($after['in_pocket'] - $before['in_pocket'], 2));
    }

    // ================================================================ date ranges

    #[TestDox('Ranges: a "from" date after the "to" date is swapped, not rejected')]
    public function test_reversed_range_is_swapped(): void
    {
        $r = $this->section('overview', ['from' => '2026-10-31', 'to' => '2026-10-01'])['range'];
        $this->assertSame('2026-10-01', $r['from']);
        $this->assertSame('2026-10-31', $r['to']);
    }

    #[TestDox('Ranges: anything longer than two years is cut to the last two years')]
    public function test_long_range_is_capped(): void
    {
        $r = $this->section('overview', ['from' => '2015-01-01', 'to' => '2026-10-31'])['range'];
        $this->assertSame('2024-10-31', $r['from']);
        $this->assertSame(731, $r['days']);
        $this->assertSame('monthly', $r['granularity']);
    }

    #[TestDox('Ranges: with no dates the last 30 days are used, compared with the 30 before')]
    public function test_default_range(): void
    {
        $r = $this->section('overview')['range'];
        $this->assertSame('2026-10-07', $r['from']);
        $this->assertSame('2026-11-05', $r['to']);
        $this->assertSame('2026-09-07', $r['previous_from']);
        $this->assertSame('2026-10-06', $r['previous_to']);
    }

    #[TestDox('Ranges: a single day is compared with the day before')]
    public function test_single_day_range(): void
    {
        $o = $this->section('overview', ['from' => '2026-10-15', 'to' => '2026-10-15']);
        $this->assertSame('2026-10-14', $o['range']['previous_from']);
        $this->assertSame('2026-10-14', $o['range']['previous_to']);
        $this->assertCount(1, $o['trend']);
    }

    #[TestDox('Ranges: daily grouping over more than six months switches to weekly')]
    public function test_daily_over_long_range_becomes_weekly(): void
    {
        $r = $this->section('overview', ['from' => '2026-01-01', 'to' => '2026-10-31', 'granularity' => 'daily'])['range'];
        $this->assertSame('weekly', $r['granularity']);
    }

    #[TestDox('Ranges: monthly buckets cover short months and month ends (31 Jan → 1 Mar)')]
    public function test_monthly_buckets_across_february(): void
    {
        $trend = $this->section('overview', ['from' => '2026-01-31', 'to' => '2026-03-01', 'granularity' => 'monthly'])['trend'];
        $this->assertSame(['Jan 2026', 'Feb 2026', 'Mar 2026'], array_column($trend, 'label'));
    }

    #[TestDox('Ranges: a malformed date or grouping is rejected with a clear validation error')]
    public function test_bad_input_is_rejected(): void
    {
        $this->actingAs($this->superadmin, 'sanctum')
            ->getJson('/api/superadmin/reports/analytics/overview?from=not-a-date')
            ->assertStatus(422)->assertJsonValidationErrors('from');
        $this->actingAs($this->superadmin, 'sanctum')
            ->getJson('/api/superadmin/reports/analytics/overview?granularity=hourly')
            ->assertStatus(422)->assertJsonValidationErrors('granularity');
    }

    // ================================================================ filters

    #[TestDox('Filters: a city with no salons returns zeros on every tab, never an error')]
    public function test_empty_city_returns_zeros_everywhere(): void
    {
        [$city] = $this->city('Emptyville');
        foreach (self::SECTIONS as $section) {
            $json = $this->section($section, ['from' => '2026-10-01', 'to' => '2026-10-31', 'city_id' => $city]);
            $this->assertSame("Emptyville {$this->tag}", $json['filters']['city'], $section);
        }
        $k = $this->section('overview', ['from' => '2026-10-01', 'to' => '2026-10-31', 'city_id' => $city])['kpis']['current'];
        $this->assertEquals(0, $k['gmv']);
        $this->assertSame(0, $k['bookings']);
        $this->assertEquals(0, $k['completion_rate']);
        $this->assertEquals(0, $k['avg_ticket']);
    }

    #[TestDox('Filters: an unknown city returns zeros; a city or area id that is not a valid id (including SQL-looking text) is refused with 422')]
    public function test_unknown_or_hostile_city_id(): void
    {
        $json = $this->section('salons', ['city_id' => (string) Str::uuid()]);
        $this->assertSame([], $json['salons']);
        $this->assertNull($json['filters']['city']);

        foreach (["x' OR '1'='1", '1; DROP TABLE salons', '42'] as $id) {
            $this->actingAs($this->superadmin, 'sanctum')
                ->getJson('/api/superadmin/reports/analytics/salons?' . http_build_query(['city_id' => $id]))
                ->assertStatus(422)->assertJsonValidationErrors('city_id');
            $this->actingAs($this->superadmin, 'sanctum')
                ->getJson('/api/superadmin/reports/analytics/places?' . http_build_query(['sub_area_id' => $id]))
                ->assertStatus(422)->assertJsonValidationErrors('sub_area_id');
        }
        $this->assertTrue(DB::getSchemaBuilder()->hasTable('salons'));
    }

    #[TestDox('Filters: the area filter keeps only salons in that area; salons without an area show as "No area set"')]
    public function test_area_filter_and_unassigned_salons(): void
    {
        [$city, $area] = $this->city();
        $inArea = $this->salon('In area', ['city_id' => $city, 'sub_area_id' => $area]);
        $noArea = $this->salon('No area', ['city_id' => $city]);
        $this->booking($inArea, '2026-10-10', 'completed', 700);
        $this->booking($noArea, '2026-10-10', 'completed', 300);
        $scope = ['from' => '2026-10-01', 'to' => '2026-10-31', 'city_id' => $city];

        $this->assertEquals(700, $this->section('overview', $scope + ['sub_area_id' => $area])['kpis']['current']['gmv']);
        $areas = collect($this->section('places', $scope)['areas'])->keyBy('name');
        $this->assertEquals(700, $areas['Lakeside']['gmv']);
        $this->assertEquals(300, $areas['No area set']['gmv']);
        $this->assertEquals(70, $areas['Lakeside']['share']);
    }

    // ================================================================ what counts as a booking

    #[TestDox('Bookings: unpaid checkouts and holds the system cancelled are not bookings; they show as abandoned')]
    public function test_abandoned_checkouts_are_not_bookings(): void
    {
        [$city] = $this->city();
        $s = $this->salon('Holds', ['city_id' => $city]);
        $this->booking($s, '2026-10-10', 'pending_payment', 500);
        $this->booking($s, '2026-10-10', 'cancelled', 500, ['cancelled_by' => 'system']);
        $this->booking($s, '2026-10-10', 'cancelled', 500, ['cancelled_by' => 'customer']);

        $k = $this->section('overview', ['from' => '2026-10-01', 'to' => '2026-10-31', 'city_id' => $city])['kpis']['current'];
        $this->assertSame(1, $k['bookings']);
        $this->assertSame(1, $k['cancelled']);
        $this->assertSame(2, $k['abandoned_checkouts']);
        $this->assertEquals(100, $k['cancellation_rate']);
    }

    #[TestDox('Bookings: walk-ins count in GMV but not as app customers or in the app booking funnel')]
    public function test_walk_ins(): void
    {
        [$city] = $this->city();
        $s = $this->salon('Walkins', ['city_id' => $city]);
        $this->booking($s, '2026-10-10', 'completed', 400, ['booking_source' => 'walk_in', 'walk_in_customer_name' => 'Wanda', 'walk_in_customer_phone' => '9111111111']);
        $this->booking($s, '2026-10-11', 'completed', 400, ['booking_source' => 'walk_in', 'walk_in_customer_name' => 'Wanda', 'walk_in_customer_phone' => '9111111111']);
        $scope = ['from' => '2026-10-01', 'to' => '2026-10-31', 'city_id' => $city];

        $k = $this->section('overview', $scope)['kpis']['current'];
        $this->assertEquals(800, $k['gmv']);
        $this->assertSame(2, $k['walk_in']);
        $this->assertSame(0, $k['customers']);
        $this->assertSame(0, $this->section('bookings', $scope)['funnel'][1]['value']);
        $this->assertSame(1, $this->section('customers', $scope)['summary']['current']['walk_in_customers']);
    }

    #[TestDox('Bookings: a completed visit without a final bill falls back to the booked total')]
    public function test_gmv_falls_back_to_total(): void
    {
        [$city] = $this->city();
        $s = $this->salon('No bill', ['city_id' => $city]);
        $this->booking($s, '2026-10-10', 'completed', 650, ['final_billed_amount' => null]);
        $this->booking($s, '2026-10-10', 'completed', 650, ['final_billed_amount' => 900]);

        $this->assertEquals(1550, $this->section('overview', ['from' => '2026-10-01', 'to' => '2026-10-31', 'city_id' => $city])['kpis']['current']['gmv']);
    }

    #[TestDox('Bookings: completion rate ignores visits that have not happened yet')]
    public function test_completion_rate_ignores_upcoming(): void
    {
        [$city] = $this->city();
        $s = $this->salon('Rates', ['city_id' => $city]);
        $this->booking($s, '2026-11-01', 'completed', 500);
        $this->booking($s, '2026-11-02', 'no_show', 500);
        $this->booking($s, '2026-11-20', 'scheduled', 500);
        $this->booking($s, '2026-11-21', 'scheduled', 500);

        $k = $this->section('overview', ['from' => '2026-11-01', 'to' => '2026-11-30', 'city_id' => $city])['kpis']['current'];
        $this->assertEquals(50, $k['completion_rate']);
        $this->assertEquals(25, $k['no_show_rate']);
        $this->assertSame(2, $k['upcoming']);
    }

    // ================================================================ totals agree

    #[TestDox('Totals: GMV is the same on the headline, the trend, the city table, the area table and the salon leaderboard')]
    public function test_totals_agree_across_views(): void
    {
        [$city, $area] = $this->city();
        $a = $this->salon('Sum A', ['city_id' => $city, 'sub_area_id' => $area]);
        $b = $this->salon('Sum B', ['city_id' => $city]);
        foreach ([[$a, '2026-10-02', 1200], [$a, '2026-10-18', 800], [$b, '2026-10-09', 450], [$b, '2026-10-31', 999]] as [$s, $d, $t]) {
            $this->booking($s, $d, 'completed', $t);
        }
        $this->booking($b, '2026-10-20', 'cancelled', 5000);
        $scope = ['from' => '2026-10-01', 'to' => '2026-10-31', 'city_id' => $city, 'granularity' => 'weekly'];

        $o = $this->section('overview', $scope);
        $gmv = $o['kpis']['current']['gmv'];
        $this->assertEquals(3449, $gmv);
        $this->assertEquals($gmv, round(array_sum(array_column($o['trend'], 'gmv')), 2));
        $p = $this->section('places', $scope);
        $this->assertEquals($gmv, round(array_sum(array_column($p['cities'], 'gmv')), 2));
        $this->assertEquals($gmv, round(array_sum(array_column($p['areas'], 'gmv')), 2));
        $this->assertEquals($gmv, round(array_sum(array_column($this->section('salons', $scope)['salons'], 'gmv')), 2));
    }

    #[TestDox('Totals: service and category revenue agree, and discounts are the original price less the price paid')]
    public function test_catalog_totals_agree(): void
    {
        [$city] = $this->city();
        $s = $this->salon('Catalog', ['city_id' => $city]);
        $cut = $this->service($s, 'Cut', 'Hair', 500, 30);
        $facial = $this->service($s, 'Facial', 'Skin', 1200, 60);
        $v1 = $this->booking($s, '2026-10-05', 'completed', 1700);
        $this->serviceLine($v1, $cut, 500, 30);
        $this->serviceLine($v1, $facial, 1000, 60, original: 1200);
        $v2 = $this->booking($s, '2026-10-06', 'cancelled', 500);
        $this->serviceLine($v2, $cut, 500, 30);

        $c = $this->section('catalog', ['from' => '2026-10-01', 'to' => '2026-10-31', 'city_id' => $city]);
        $this->assertEquals(1500, array_sum(array_column($c['categories'], 'revenue')));
        $this->assertEquals(1500, array_sum(array_column($c['services'], 'revenue')));
        $services = collect($c['services'])->keyBy('name');
        $this->assertSame(2, $services["Cut {$this->tag}"]['lines']);
        $this->assertSame(1, $services["Cut {$this->tag}"]['completed']);
        $this->assertEquals(200, $services["Facial {$this->tag}"]['discount']);
        $this->assertEquals(1000, $services["Facial {$this->tag}"]['revenue_per_hour']);
    }

    #[TestDox('Totals: growth is blank (not 100% or infinite) when the previous period had nothing')]
    public function test_growth_without_previous_period(): void
    {
        [$city] = $this->city();
        $s = $this->salon('Fresh', ['city_id' => $city]);
        $this->booking($s, '2026-10-10', 'completed', 500);

        $row = collect($this->section('salons', ['from' => '2026-10-01', 'to' => '2026-10-31', 'city_id' => $city])['salons'])->firstWhere('id', $s->id);
        $this->assertNull($row['growth']);
        $this->assertEquals(0, $row['previous_gmv']);
    }

    // ================================================================ customers

    #[TestDox('Customers: someone who visited before the range is returning; a cancelled visit never makes anyone "new"')]
    public function test_new_versus_returning(): void
    {
        [$city] = $this->city();
        $s = $this->salon('Loyal', ['city_id' => $city]);
        $old = $this->user('customer');
        $new = $this->user('customer');
        $this->booking($s, '2026-08-15', 'completed', 500, ['customer_id' => $old->id]);
        $this->booking($s, '2026-10-12', 'completed', 500, ['customer_id' => $old->id]);
        $this->booking($s, '2026-09-01', 'cancelled', 500, ['customer_id' => $new->id]);
        $this->booking($s, '2026-10-14', 'completed', 500, ['customer_id' => $new->id]);

        $c = $this->section('customers', ['from' => '2026-10-01', 'to' => '2026-10-31', 'city_id' => $city])['summary']['current'];
        $this->assertSame(2, $c['customers']);
        $this->assertSame(1, $c['new']);
        $this->assertSame(1, $c['returning']);
    }

    #[TestDox('Customers: phone numbers in the top-customers list are masked to the last four digits')]
    public function test_top_customer_phone_is_masked(): void
    {
        [$city] = $this->city();
        $s = $this->salon('Privacy', ['city_id' => $city]);
        $c = $this->user('customer', ['phone' => '9876543210']);
        $this->booking($s, '2026-10-10', 'completed', 900, ['customer_id' => $c->id]);

        $top = $this->section('customers', ['from' => '2026-10-01', 'to' => '2026-10-31', 'city_id' => $city])['top'][0];
        $this->assertSame('••••3210', $top['phone']);
        $this->assertStringNotContainsString('98765', json_encode($top));
    }

    // ================================================================ teams

    #[TestDox('Teams: utilisation uses each member\'s hours, skips weekly offs and approved leave, and ignores cancelled bookings')]
    public function test_provider_utilisation(): void
    {
        [$city] = $this->city();
        $s = $this->salon('Team', ['city_id' => $city]);
        $pid = $this->providers[$s->id];
        DB::table('service_providers')->where('id', $pid)->update(['use_salon_hours' => false]);
        foreach (range(0, 6) as $dow) {
            DB::table('provider_working_hours')->insert([
                'id' => (string) Str::uuid(), 'provider_id' => $pid, 'day_of_week' => $dow, 'is_weekly_off' => $dow === 0,
                'shift_start' => '10:00:00', 'shift_end' => '19:00:00', 'break_start' => '13:00:00', 'break_end' => '14:00:00',
            ]);
        }
        DB::table('provider_leaves')->insert(['id' => (string) Str::uuid(), 'provider_id' => $pid, 'leave_date' => '2026-10-07', 'is_full_day' => true, 'status' => 'approved']);
        DB::table('provider_leaves')->insert(['id' => (string) Str::uuid(), 'provider_id' => $pid, 'leave_date' => '2026-10-08', 'is_full_day' => true, 'status' => 'pending']);

        $svc = $this->service($s, 'Colour', 'Hair', 2000, 60);
        $done = $this->booking($s, '2026-10-05', 'completed', 2000);
        $this->serviceLine($done, $svc, 2000, 60, $pid);
        $later = $this->booking($s, '2026-10-09', 'scheduled', 2000);
        $this->serviceLine($later, $svc, 2000, 60, $pid);
        $gone = $this->booking($s, '2026-10-06', 'cancelled', 2000);
        $this->serviceLine($gone, $svc, 2000, 60, $pid);

        // Mon 5 Oct – Sun 11 Oct: six working days of 8 hours, less one approved leave day.
        $row = collect($this->section('salons', ['from' => '2026-10-05', 'to' => '2026-10-11', 'city_id' => $city])['providers'])->firstWhere('id', $pid);
        $this->assertSame(5 * 480, $row['capacity_minutes']);
        $this->assertSame(120, $row['booked_minutes']);
        $this->assertSame(1, $row['leave_days']);
        $this->assertEquals(5, $row['utilisation']);
        $this->assertEquals(2000, $row['revenue']);
    }

    // ================================================================ engagement

    #[TestDox('Engagement: only reviews written in the range count, and "lowest rated" needs three reviews')]
    public function test_reviews_in_range_and_minimum_for_lowest(): void
    {
        [$city] = $this->city();
        $few = $this->salon('Few reviews', ['city_id' => $city]);
        $many = $this->salon('Many reviews', ['city_id' => $city]);
        $review = function (Salon $s, int $stars, string $at) {
            $a = $this->booking($s, substr($at, 0, 10), 'completed', 500);
            DB::table('reviews')->insert(['id' => (string) Str::uuid(), 'appointment_id' => $a->id, 'customer_id' => $this->user('customer')->id, 'salon_id' => $s->id, 'rating' => $stars, 'created_at' => $at, 'updated_at' => $at]);
        };
        $review($few, 1, '2026-10-05 10:00:00');
        $review($few, 1, '2026-10-06 10:00:00');
        foreach ([3, 4, 5] as $i => $stars) {
            $review($many, $stars, '2026-10-1' . $i . ' 10:00:00');
        }
        $review($many, 1, '2026-09-20 10:00:00');   // before the range

        $r = $this->section('engagement', ['from' => '2026-10-01', 'to' => '2026-10-31', 'city_id' => $city])['reviews'];
        $this->assertSame(5, $r['count']);
        $this->assertEquals(2.8, $r['avg_rating']);
        $this->assertSame([$many->id], array_column($r['lowest_rated'], 'id'));
    }

    // ================================================================ access

    #[TestDox('Access: signed-out visitors get 401 and salon owners get 403 on every report endpoint')]
    public function test_access_control(): void
    {
        $paths = array_merge(['cash-position'], array_map(fn ($s) => "analytics/{$s}", array_merge(['options'], self::SECTIONS)));
        foreach ($paths as $path) {
            $this->getJson("/api/superadmin/reports/{$path}")->assertUnauthorized();
            $this->actingAs($this->owner, 'sanctum')->getJson("/api/superadmin/reports/{$path}")->assertForbidden();
            $this->app['auth']->forgetGuards();
        }
    }
}
