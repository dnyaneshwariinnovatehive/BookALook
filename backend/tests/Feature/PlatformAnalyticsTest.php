<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\Salon;
use App\Models\SalonPayout;
use App\Models\SalonPayoutItem;
use App\Models\ServiceProvider;
use App\Models\SubscriptionPlan;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * SuperAdmin money-in-pocket card and the analytics dashboard behind
 * Platform Reporting.
 *
 * The suite shares a database with other tests, so the cash position (which
 * is all-time and platform-wide) is checked as the change our rows make, and
 * the analytics sections are checked inside a city of our own.
 */
class PlatformAnalyticsTest extends TestCase
{
    use DatabaseTransactions;

    private User $superadmin;
    private User $owner;
    private string $tag;

    /** @var array<string, string> salon id => a team member to book with */
    private array $providers = [];

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-11-05 10:00:00');
        config(['services.payments.razorpay.fee_percent' => 2.36]);

        $this->tag = substr(bin2hex(random_bytes(6)), 0, 8);
        $this->superadmin = $this->user('superadmin');
        $this->owner = $this->user('admin');
    }

    // ── helpers ───────────────────────────────────────────────────────────

    private function user(string $role, array $extra = []): User
    {
        return User::create(array_merge([
            'id' => (string) Str::uuid(), 'role' => $role, 'name' => ucfirst($role) . ' ' . Str::random(4),
            'phone' => '4' . random_int(100000000, 999999999), 'password_hash' => 'x', 'is_active' => true,
        ], $extra));
    }

    private function salon(string $name, array $extra = []): Salon
    {
        $salon = Salon::create(array_merge([
            'admin_id' => $this->owner->id, 'name' => "{$name} {$this->tag}", 'slug' => Str::slug($name) . '-' . Str::random(8),
            'address' => 'x', 'status' => 'active', 'submitted_by' => $this->owner->id,
        ], $extra));
        $this->providers[$salon->id] = ServiceProvider::create(['user_id' => $this->user('service_provider')->id, 'salon_id' => $salon->id, 'is_active' => true])->id;

        return $salon;
    }

    private function booking(Salon $salon, string $date, string $status, float $total, array $extra = []): Appointment
    {
        return Appointment::create(array_merge([
            'salon_id' => $salon->id,
            'appointed_provider_id' => $this->providers[$salon->id],
            'booking_source' => 'online',
            'appointment_date' => $date,
            'start_time' => '11:00:00',
            'end_time' => '11:30:00',
            'status' => $status,
            'total_amount' => $total,
            'final_billed_amount' => $status === 'completed' ? $total : null,
            'advance_amount' => 0,
            'balance_amount' => $total,
        ], $extra));
    }

    private function pay(Appointment $a, float $amount, ?string $gateway = 'razorpay', string $at = '2026-10-20 10:00:00', string $type = 'advance'): string
    {
        $id = (string) Str::uuid();
        DB::table('payments')->insert([
            'id' => $id, 'appointment_id' => $a->id, 'amount' => $amount, 'payment_type' => $type,
            'payment_mode' => $gateway ? 'online' : 'cash', 'gateway' => $gateway, 'status' => 'success',
            'paid_at' => $at, 'created_at' => $at, 'updated_at' => $at,
        ]);

        return $id;
    }

    private function refund(Appointment $a, string $paymentId, float $amount, string $status, string $at = '2026-10-21 10:00:00'): void
    {
        DB::table('payment_refunds')->insert([
            'id' => (string) Str::uuid(), 'payment_id' => $paymentId, 'appointment_id' => $a->id, 'amount' => $amount,
            'reason' => 'Cancelled in time', 'status' => $status, 'created_at' => $at, 'updated_at' => $at,
        ]);
    }

    private function payout(Salon $salon, string $status, float $gross, float $commission, float $net, array $claims = [], string $start = '2026-10-01'): SalonPayout
    {
        $payout = SalonPayout::create([
            'salon_id' => $salon->id, 'cycle_type' => 'monthly', 'billing_type' => 'commission',
            'cycle_start_date' => $start, 'cycle_end_date' => Carbon::parse($start)->endOfMonth()->toDateString(), 'status' => $status,
            'gross_amount' => $gross, 'appointment_revenue' => $gross, 'appointments_count' => count($claims),
            'commission_deducted' => $commission, 'refund_adjustment' => 0, 'wallet_redeemed_amount' => 0,
            'net_amount' => $net, 'distributed_at' => $status === 'distributed' ? '2026-10-31 12:00:00' : null,
        ]);
        foreach ($claims as $a) {
            SalonPayoutItem::create([
                'salon_payout_id' => $payout->id, 'kind' => SalonPayoutItem::KIND_BOOKING, 'appointment_id' => $a->id,
                'appointment_status' => $a->status, 'gross_amount' => $gross, 'commission_base' => $gross,
                'commission_rate' => 10, 'commission_amount' => $commission, 'refund_amount' => 0, 'net_amount' => $gross - $commission,
            ]);
        }

        return $payout;
    }

    private function planPayment(Salon $salon, string $status, float $cash, string $at = '2026-10-15 10:00:00'): void
    {
        $plan = SubscriptionPlan::create(['name' => 'Plan ' . Str::random(5), 'price' => $cash, 'validity_days' => 30, 'is_active' => true]);
        DB::table('subscription_payment_requests')->insert([
            'salon_id' => $salon->id, 'subscription_plan_id' => $plan->id, 'billing_type' => 'subscription',
            'screenshot_url' => 'x.png', 'status' => $status, 'coins_to_redeem' => 0, 'coin_discount_inr' => 0,
            'amount_payable_inr' => $cash, 'created_at' => $at, 'updated_at' => $at,
        ]);
    }

    private function cash(): array
    {
        return $this->actingAs($this->superadmin, 'sanctum')
            ->getJson('/api/superadmin/reports/cash-position')
            ->assertOk()
            ->json();
    }

    private function line(array $json, string $group, string $key): float
    {
        return (float) collect($json[$group])->firstWhere('key', $key)['amount'];
    }

    private function section(string $section, array $query = []): array
    {
        return $this->actingAs($this->superadmin, 'sanctum')
            ->getJson('/api/superadmin/reports/analytics/' . $section . '?' . http_build_query($query))
            ->assertOk()
            ->assertJsonPath('success', true)
            ->json();
    }

    // ── money in pocket ───────────────────────────────────────────────────

    public function test_money_in_pocket_is_cash_held_less_what_is_still_owed_out(): void
    {
        $before = $this->cash();
        $salon = $this->salon('Pocket');

        // Settled: the salon was paid 450 of a 500 advance (commission 50).
        $settled = $this->booking($salon, '2026-10-05', 'completed', 1000);
        $this->pay($settled, 500);
        $this->payout($salon, 'distributed', 500, 50, 450, [$settled], '2026-09-01');

        // Upcoming visit: its 300 advance is held for the salon.
        $upcoming = $this->booking($salon, '2026-11-12', 'scheduled', 900);
        $this->pay($upcoming, 300, 'demo');

        // Cancelled and refunded in full / refund still queued.
        $refunded = $this->booking($salon, '2026-10-08', 'cancelled', 600);
        $this->refund($refunded, $this->pay($refunded, 200, 'demo'), 200, 'processed');
        $queued = $this->booking($salon, '2026-10-09', 'cancelled', 600);
        $this->refund($queued, $this->pay($queued, 100, 'demo'), 100, 'pending');

        // In a payout not yet paid: BookALook owes 380 of 400.
        $open = $this->booking($salon, '2026-10-10', 'completed', 800);
        $this->pay($open, 400, 'demo');
        $this->payout($salon, 'approved', 400, 20, 380, [$open], '2026-10-01');

        // A commission salon paid its dues; another still owes.
        $this->payout($this->salon('Dues paid'), 'distributed', 0, 250, -250);
        $this->payout($this->salon('Dues open'), 'pending', 0, 120, -120);

        // Plan payments: one approved, one waiting for SuperAdmin.
        $this->planPayment($salon, 'approved', 999);
        $this->planPayment($salon, 'pending', 499);

        // Cash at the counter is the salon's and never counts.
        $this->pay($settled, 1000, null);

        $after = $this->cash();
        $d = fn (string $group, string $key) => round($this->line($after, $group, $key) - $this->line($before, $group, $key), 2);

        $this->assertEquals(1500, $d('cash_in', 'online_collected'));
        $this->assertEquals(999, $d('cash_in', 'plan_payments'));
        $this->assertEquals(250, $d('cash_in', 'dues_collected'));
        $this->assertEquals(450, $d('cash_out', 'paid_to_salons'));
        $this->assertEquals(200, $d('cash_out', 'refunds_paid'));
        $this->assertEquals(11.8, $d('cash_out', 'gateway_fee'));   // 2.36% of the 500 through Razorpay
        $this->assertEquals(380, $d('owed_out', 'open_payouts'));
        $this->assertEquals(300, $d('owed_out', 'unsettled_advances'));
        $this->assertEquals(100, $d('owed_out', 'refunds_queued'));
        $this->assertEquals(120, $d('not_counted', 'dues_receivable'));
        $this->assertEquals(499, $d('not_counted', 'plans_pending'));

        $this->assertEquals(2087.2, round($after['cash_held'] - $before['cash_held'], 2));
        $this->assertEquals(780, round($after['still_owed'] - $before['still_owed'], 2));
        // What BookALook keeps: commission 50 + 20, dues 250, plan 999, less the fee.
        $this->assertEquals(1307.2, round($after['in_pocket'] - $before['in_pocket'], 2));
        $this->assertEquals(
            round($after['cash_held'] - $after['still_owed'], 2),
            $after['in_pocket']
        );
    }

    public function test_only_superadmin_sees_the_cash_position_and_analytics(): void
    {
        $this->actingAs($this->owner, 'sanctum')->getJson('/api/superadmin/reports/cash-position')->assertForbidden();
        $this->actingAs($this->owner, 'sanctum')->getJson('/api/superadmin/reports/analytics/overview')->assertForbidden();
        $this->actingAs($this->superadmin, 'sanctum')->getJson('/api/superadmin/reports/analytics/nonsense')->assertNotFound();
    }

    // ── analytics ─────────────────────────────────────────────────────────

    /**
     * A small city of our own: two salons (one in an area), three customers,
     * a month of bookings and the month before for comparison.
     *
     * @return array{city: string, area: string, a: Salon, b: Salon, c1: User, c2: User, c3: User}
     */
    private function market(): array
    {
        $city = (string) Str::uuid();
        DB::table('cities')->insert(['id' => $city, 'name' => "Testpur {$this->tag}", 'state' => 'Test', 'is_active' => true, 'created_at' => now(), 'updated_at' => now()]);
        $area = (string) Str::uuid();
        DB::table('sub_areas')->insert(['id' => $area, 'city_id' => $city, 'name' => 'Lakeside', 'is_active' => true, 'created_at' => now(), 'updated_at' => now()]);

        $a = $this->salon('Alpha', ['city_id' => $city, 'sub_area_id' => $area]);
        $b = $this->salon('Beta', ['city_id' => $city, 'commission_opt_in' => true]);
        $c1 = $this->user('customer', ['city_id' => $city, 'sub_area_id' => $area, 'gender' => 'female']);
        $c2 = $this->user('customer', ['city_id' => $city, 'sub_area_id' => $area, 'gender' => 'male']);
        $c3 = $this->user('customer', ['city_id' => $city]);

        return compact('city', 'area', 'a', 'b', 'c1', 'c2', 'c3');
    }

    public function test_analytics_sections_add_up_inside_a_city(): void
    {
        ['city' => $city, 'area' => $area, 'a' => $a, 'b' => $b, 'c1' => $c1, 'c2' => $c2, 'c3' => $c3] = $this->market();

        // Previous period (Sep): c1 visits Alpha once.
        $this->booking($a, '2026-09-20', 'completed', 500, ['customer_id' => $c1->id]);

        // This period (Oct).
        $v1 = $this->booking($a, '2026-10-02', 'completed', 1000, ['customer_id' => $c1->id, 'start_time' => '10:00:00']);   // Fri
        $this->booking($a, '2026-10-09', 'completed', 1200, ['customer_id' => $c1->id, 'start_time' => '10:30:00']);         // Fri
        $v3 = $this->booking($b, '2026-10-03', 'completed', 800, ['customer_id' => $c2->id, 'start_time' => '17:00:00']);    // Sat
        $this->booking($b, '2026-10-04', 'cancelled', 700, ['customer_id' => $c3->id, 'cancelled_by' => 'customer', 'cancellation_reason' => 'Busy']);
        $this->booking($b, '2026-10-05', 'no_show', 600, ['customer_id' => $c3->id]);
        $this->booking($a, '2026-10-06', 'completed', 400, ['booking_source' => 'walk_in', 'walk_in_customer_name' => 'Wally', 'walk_in_customer_phone' => '9000000000']);
        // An expired checkout is not a booking.
        $this->booking($a, '2026-10-07', 'cancelled', 900, ['customer_id' => $c3->id, 'cancelled_by' => 'system']);

        $this->pay($v1, 300, 'razorpay', '2026-10-01 09:00:00');
        $this->pay($v1, 700, null, '2026-10-02 11:00:00', 'balance');
        $this->pay($v3, 800, 'razorpay', '2026-10-02 09:00:00', 'full');
        $this->payout($b, 'distributed', 800, 80, 720, [$v3]);
        DB::table('reviews')->insert(['id' => (string) Str::uuid(), 'appointment_id' => $v1->id, 'customer_id' => $c1->id, 'salon_id' => $a->id, 'rating' => 4, 'created_at' => '2026-10-02 20:00:00', 'updated_at' => '2026-10-02 20:00:00']);

        $scope = ['from' => '2026-10-01', 'to' => '2026-10-31', 'city_id' => $city];

        // Overview
        $o = $this->section('overview', $scope);
        $k = $o['kpis']['current'];
        $this->assertSame('2026-09-30', $o['range']['previous_to']);
        $this->assertSame("Testpur {$this->tag}", $o['filters']['city']);
        $this->assertEquals(3400, $k['gmv']);
        $this->assertSame(6, $k['bookings']);
        $this->assertSame(4, $k['completed']);
        $this->assertSame(1, $k['cancelled']);
        $this->assertSame(1, $k['no_show']);
        $this->assertSame(1, $k['walk_in']);
        $this->assertSame(1, $k['abandoned_checkouts']);
        $this->assertEquals(850, $k['avg_ticket']);
        $this->assertSame(2, $k['customers']);
        $this->assertSame(1, $k['new_customers']);          // c2; c1 first came in September
        $this->assertEquals(1100, $k['online_collected']);
        $this->assertEquals(700, $k['at_salon_collected']);
        $this->assertEquals(80, $k['commission']);
        $this->assertEquals(720, $k['paid_to_salons']);
        $this->assertEquals(4.0, $k['avg_rating']);
        $this->assertEquals(500, $o['kpis']['previous']['gmv']);
        $this->assertEquals(3400, array_sum(array_column($o['trend'], 'gmv')));
        $this->assertCount(31, $o['trend']);

        // Money
        $m = $this->section('money', $scope);
        $mix = collect($m['payment_mix'])->keyBy('key');
        $this->assertSame(1, $mix['full']['bookings']);
        $this->assertSame(1, $mix['advance']['bookings']);
        $this->assertSame(4, $mix['at_salon']['bookings']);
        $this->assertEquals(300, $m['flows']['current']['online_advance']);
        $this->assertEquals(round(1100 * 0.0236, 2), $m['flows']['current']['gateway_fee_estimate']);
        $this->assertArrayHasKey('in_pocket', $m['cash_position']);

        // Bookings
        $bk = $this->section('bookings', $scope);
        $this->assertSame([['label' => 'Customer', 'count' => 1]], $bk['cancelled_by']);
        $this->assertSame('Busy', $bk['cancellation_reasons'][0]['reason']);
        $fri = collect($bk['heatmap']['rows'])->firstWhere('day', 'Fri');
        $this->assertSame(2, collect($fri['cells'])->firstWhere('hour', 10)['count']);
        $this->assertSame(2, collect($bk['by_weekday'])->firstWhere('day', 'Fri')['bookings']);
        $this->assertSame(5, $bk['funnel'][1]['value']);    // app bookings confirmed (walk-in excluded)
        $this->assertSame(6, $bk['funnel'][0]['value']);    // plus the abandoned checkout

        // Places
        $p = $this->section('places', $scope);
        $this->assertCount(1, $p['cities']);
        $this->assertEquals(3400, $p['cities'][0]['gmv']);
        $this->assertSame(3, $p['cities'][0]['customers_living']);
        $areas = collect($p['areas'])->keyBy('name');
        $this->assertEquals(2600, $areas['Lakeside']['gmv']);
        $this->assertSame(2, $areas['Lakeside']['customers_living']);
        $this->assertEquals(800, $areas['No area set']['gmv']);

        // Salons
        $s = collect($this->section('salons', $scope)['salons'])->keyBy('id');
        $this->assertEquals(2600, $s[$a->id]['gmv']);
        $this->assertEquals(500, $s[$a->id]['previous_gmv']);
        $this->assertEquals(420, $s[$a->id]['growth']);
        $this->assertSame(1, $s[$a->id]['repeat_customers']);
        $this->assertEquals(80, $s[$b->id]['commission']);
        $this->assertEquals(33.3, $s[$b->id]['cancellation_rate']);
        $this->assertSame('Commission Model', $s[$b->id]['billing']);

        // Area filter narrows to Alpha only.
        $onlyArea = $this->section('overview', $scope + ['sub_area_id' => $area]);
        $this->assertEquals(2600, $onlyArea['kpis']['current']['gmv']);

        // Customers
        $cu = $this->section('customers', $scope);
        $this->assertSame(2, $cu['summary']['current']['customers']);
        $this->assertSame(1, $cu['summary']['current']['new']);
        $this->assertSame(1, $cu['summary']['current']['repeaters']);
        $sep = collect($cu['cohorts'])->firstWhere('cohort', '2026-09');
        $this->assertSame(1, $sep['size']);
        $this->assertEquals(100, $sep['retention'][1]['rate']);   // c1 came back in October
        $this->assertSame(1, collect($cu['frequency'])->firstWhere('label', '2 visits')['customers']);

        // Engagement
        $e = $this->section('engagement', $scope);
        $this->assertSame(1, $e['reviews']['count']);
        $this->assertSame(1, collect($e['reviews']['distribution'])->firstWhere('stars', 4)['count']);

        // Options list our city with its area.
        $opt = collect($this->section('options')['cities'])->firstWhere('id', $city);
        $this->assertSame('Lakeside', $opt['areas'][0]['name']);
        $this->assertSame(2, $opt['salons']);
    }

    public function test_every_section_answers_unfiltered_with_weekly_and_monthly_buckets(): void
    {
        foreach (['overview', 'money', 'bookings', 'places', 'salons', 'catalog', 'customers', 'engagement'] as $section) {
            $weekly = $this->section($section, ['from' => '2026-08-01', 'to' => '2026-10-31', 'granularity' => 'weekly']);
            $this->assertSame('weekly', $weekly['range']['granularity']);
        }

        $monthly = $this->section('overview', ['from' => '2026-01-01', 'to' => '2026-10-31']);
        $this->assertSame('monthly', $monthly['range']['granularity']);
        $this->assertCount(10, $monthly['trend']);
        $this->assertSame('2025-03-03', $monthly['range']['previous_from']);
    }
}
