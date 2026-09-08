<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\Salon;
use App\Models\SalonCommissionRate;
use App\Models\SalonPayout;
use App\Models\SalonSubscription;
use App\Models\ServiceProvider;
use App\Models\SubscriptionPaymentRequest;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Services\CommissionService;
use App\Services\PayoutService;
use App\Services\SalonAccessService;
use App\Support\BillingModel;
use App\Support\PayoutCycle;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * The two ways a salon pays to trade, and the rules that keep them apart.
 *
 * A Subscription Plan is prepaid and expires. The Commission Model is postpaid,
 * settled monthly on the 1st, and the salon keeps trading only for as long as
 * it keeps settling. The percentage is SuperAdmin's to set, and it cannot move
 * while the salon still owes on the old one.
 *
 * Runs in a transaction so it can use the development database without leaving
 * anything behind.
 */
class BillingModelTest extends TestCase
{
    use DatabaseTransactions;

    // --------------------------------------------------------- the two models

    public function test_a_commission_salon_settles_monthly_and_a_subscription_salon_weekly(): void
    {
        [$commissionSalon, , $providerA] = $this->fixture();
        [$planSalon, , $providerB] = $this->fixture();

        $this->onCommissionModel($commissionSalon, 10.0);
        $this->onSubscriptionPlan($planSalon);

        $today = Carbon::today();
        $this->givenCompleted($commissionSalon, $providerA, 2000, 500, $today);
        $this->givenCompleted($planSalon, $providerB, 2000, 500, $today);

        $payouts = app(PayoutService::class);
        $payouts->generateMonthly($today);
        $payouts->generateWeekly($today);

        $commissionPayout = SalonPayout::where('salon_id', $commissionSalon->id)->first();
        $planPayout = SalonPayout::where('salon_id', $planSalon->id)->first();

        $this->assertSame(PayoutCycle::MONTHLY, $commissionPayout->cycle_type);
        $this->assertEquals(200.0, (float) $commissionPayout->commission_deducted);

        $this->assertSame(PayoutCycle::WEEKLY, $planPayout->cycle_type);
        // Already paid for access, so nothing is taken off the advances.
        $this->assertEquals(0.0, (float) $planPayout->commission_deducted);
        $this->assertEquals(500.0, (float) $planPayout->net_amount);
    }

    public function test_the_weekly_run_leaves_commission_salons_alone(): void
    {
        [$salon, , $provider] = $this->fixture();
        $this->onCommissionModel($salon, 10.0);

        $today = Carbon::today();
        $this->givenCompleted($salon, $provider, 1000, 300, $today);

        app(PayoutService::class)->generateWeekly($today);

        // Billing the same month in four weekly pieces would charge commission
        // on a rhythm the salon was never told about.
        $this->assertSame(0, SalonPayout::where('salon_id', $salon->id)->count());
    }

    // ------------------------------------------------------- changing the rate

    public function test_the_rate_cannot_change_while_a_payout_is_still_open(): void
    {
        [$salon, $superAdmin, $provider] = $this->fixture();
        $this->onCommissionModel($salon, 10.0);

        [$start, $end] = $this->thisMonth();
        $this->givenCompleted($salon, $provider, 5000, 1000, $start);
        app(PayoutService::class)->calculate($salon->id, $start, $end);

        $response = $this->actingAs($superAdmin, 'sanctum')
            ->putJson("/api/superadmin/salons/{$salon->id}/commission-rate", [
                'commission_percentage' => 20.0,
            ])
            ->assertStatus(422);

        $this->assertStringContainsString('Settle', $response->json('message'));
        $this->assertCount(1, $response->json('unsettled_payouts'));

        // The salon is still on the rate it was told about.
        $this->assertEquals(10.0, (float) $salon->fresh()->commission_percentage);
    }

    public function test_the_rate_changes_once_every_payout_is_settled(): void
    {
        [$salon, $superAdmin, $provider] = $this->fixture();
        $this->onCommissionModel($salon, 10.0);

        [$start, $end] = $this->thisMonth();
        $this->givenCompleted($salon, $provider, 5000, 1000, $start);

        $payouts = app(PayoutService::class);
        $payout = $payouts->calculate($salon->id, $start, $end);
        $payouts->markDistributed($payouts->approve($payout, $superAdmin), $superAdmin, 'NEFT-1');

        $this->actingAs($superAdmin, 'sanctum')
            ->putJson("/api/superadmin/salons/{$salon->id}/commission-rate", [
                'commission_percentage' => 18.5,
                'reason' => 'Renegotiated.',
            ])
            ->assertStatus(200);

        $this->assertEquals(18.5, (float) $salon->fresh()->commission_percentage);

        // The old rate is closed, not deleted — the settled payout above still
        // has to be explainable.
        $rates = SalonCommissionRate::where('salon_id', $salon->id)->orderBy('effective_from')->get();
        $this->assertCount(2, $rates);
        $this->assertNotNull($rates->first()->effective_to);
        $this->assertNull($rates->last()->effective_to);
        $this->assertEquals(18.5, (float) $rates->last()->percentage);
    }

    public function test_a_settled_payout_keeps_the_rate_it_was_charged_at(): void
    {
        [$salon, $superAdmin, $provider] = $this->fixture();
        $this->onCommissionModel($salon, 10.0);

        [$start, $end] = $this->thisMonth();
        $this->givenCompleted($salon, $provider, 5000, 2000, $start);

        $payouts = app(PayoutService::class);
        $settled = $payouts->calculate($salon->id, $start, $end);
        $payouts->markDistributed($payouts->approve($settled, $superAdmin), $superAdmin, 'NEFT-2');

        app(CommissionService::class)->setRate($salon->fresh(), 25.0, $superAdmin, 'New deal.');

        // Recalculating a distributed cycle must not re-price it at the new rate.
        $again = $payouts->calculate($salon->id, $start, $end);
        $this->assertEquals(10.0, (float) $again->commission_percentage_snapshot);
        $this->assertEquals(500.0, (float) $again->commission_deducted);

        // The next cycle is charged at the new rate.
        $nextStart = $start->copy()->addMonthNoOverflow();
        $this->givenCompleted($salon, $provider, 4000, 1000, $nextStart);
        $next = $payouts->calculate($salon->id, $nextStart, $nextStart->copy()->endOfMonth());

        $this->assertEquals(25.0, (float) $next->commission_percentage_snapshot);
        $this->assertEquals(1000.0, (float) $next->commission_deducted);
    }

    public function test_a_subscription_salon_has_no_rate_to_set(): void
    {
        [$salon, $superAdmin] = $this->fixture();
        $this->onSubscriptionPlan($salon);

        $this->actingAs($superAdmin, 'sanctum')
            ->putJson("/api/superadmin/salons/{$salon->id}/commission-rate", [
                'commission_percentage' => 12.0,
            ])
            ->assertStatus(422)
            ->assertJsonPath('success', false);
    }

    // ------------------------------------------------------------ the window

    public function test_settling_a_month_buys_the_salon_the_next_one(): void
    {
        [$salon, $superAdmin, $provider] = $this->fixture();
        $this->onCommissionModel($salon, 10.0);

        $commission = app(CommissionService::class);
        $before = SalonSubscription::where('salon_id', $salon->id)->latest('start_date')->first();

        // Joining buys the month joined in and nothing more.
        [$thisMonth] = $this->thisMonth();
        $this->assertSame(
            $commission->accessEndFrom($thisMonth->copy()->subMonthNoOverflow())->toDateString(),
            Carbon::parse($before->end_date)->toDateString()
        );

        // Settling that month buys the one after it. In practice the run lands
        // on the 1st; the mechanic is the same whenever it is settled.
        $this->givenCompleted($salon, $provider, 3000, 1000, $thisMonth);

        $payouts = app(PayoutService::class);
        $payout = $payouts->calculate($salon->id, $thisMonth, $thisMonth->copy()->endOfMonth());
        $payouts->markDistributed($payouts->approve($payout, $superAdmin), $superAdmin, 'NEFT-3');

        $this->assertSame(
            $commission->accessEndFrom($thisMonth)->toDateString(),
            Carbon::parse($before->fresh()->end_date)->toDateString()
        );
    }

    public function test_settling_an_old_month_late_cannot_shorten_the_window(): void
    {
        [$salon, $superAdmin, $provider] = $this->fixture();
        $this->onCommissionModel($salon, 10.0);

        [$thisMonth] = $this->thisMonth();
        $payouts = app(PayoutService::class);

        // Settle this month first, then an older one out of order.
        $this->givenCompleted($salon, $provider, 3000, 1000, $thisMonth);
        $current = $payouts->calculate($salon->id, $thisMonth, $thisMonth->copy()->endOfMonth());
        $payouts->markDistributed($payouts->approve($current, $superAdmin), $superAdmin, 'NEFT-A');

        $earned = Carbon::parse(
            SalonSubscription::where('salon_id', $salon->id)->latest('start_date')->first()->end_date
        );

        $old = $thisMonth->copy()->subMonthsNoOverflow(2);
        $this->givenCompleted($salon, $provider, 1000, 200, $old);
        $stale = $payouts->calculate($salon->id, $old, $old->copy()->endOfMonth());
        $payouts->markDistributed($payouts->approve($stale, $superAdmin), $superAdmin, 'NEFT-B');

        $this->assertSame(
            $earned->toDateString(),
            Carbon::parse(
                SalonSubscription::where('salon_id', $salon->id)->latest('start_date')->first()->end_date
            )->toDateString()
        );
    }

    public function test_an_unsettled_month_takes_the_salon_offline(): void
    {
        [$salon] = $this->fixture();
        $this->onCommissionModel($salon, 10.0);

        // Push the window back past the grace the platform allows.
        SalonSubscription::where('salon_id', $salon->id)
            ->update(['end_date' => Carbon::yesterday()->toDateString()]);

        $status = app(SalonAccessService::class)->status($salon->fresh());

        $this->assertFalse($status['is_active']);
        // Not "renew your plan" — there is nothing to renew on a postpaid model.
        $this->assertSame(SalonAccessService::REASON_COMMISSION_UNSETTLED, $status['reason']);
        $this->assertSame(BillingModel::COMMISSION, $status['billing_model']);
    }

    public function test_settling_brings_a_locked_out_salon_back(): void
    {
        [$salon, $superAdmin, $provider] = $this->fixture();
        $this->onCommissionModel($salon, 10.0);

        $lastMonth = Carbon::today()->subMonthNoOverflow()->startOfMonth();
        $this->givenCompleted($salon, $provider, 2000, 500, $lastMonth);

        SalonSubscription::where('salon_id', $salon->id)->update([
            'end_date' => Carbon::yesterday()->toDateString(),
            'status' => 'expired',
        ]);

        $payouts = app(PayoutService::class);
        $payout = $payouts->calculate($salon->id, $lastMonth, $lastMonth->copy()->endOfMonth());
        $payouts->markDistributed($payouts->approve($payout, $superAdmin), $superAdmin, 'NEFT-4');

        $this->assertTrue(app(SalonAccessService::class)->status($salon->fresh())['is_active']);
    }

    // --------------------------------------------------------- joining/leaving

    public function test_a_salon_asks_for_the_commission_model_and_superadmin_sets_the_rate(): void
    {
        [$salon, $superAdmin] = $this->fixture();
        $this->onSubscriptionPlan($salon);
        $this->givenCommissionPlan();

        $owner = User::find($salon->admin_id);

        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/subscription/commission-request")
            ->assertStatus(200);

        $request = SubscriptionPaymentRequest::where('salon_id', $salon->id)
            ->where('status', 'pending')
            ->first();

        $this->assertNotNull($request);
        $this->assertSame(BillingModel::COMMISSION, $request->billing_type);
        // Postpaid: nothing was paid, so there is no receipt to verify.
        $this->assertNull($request->screenshot_url);

        // The salon does not get to name its own percentage.
        $this->actingAs($superAdmin, 'sanctum')
            ->postJson("/api/superadmin/salons/{$salon->id}/subscription", [
                'billing_type' => BillingModel::COMMISSION,
                'commission_percentage' => 14.0,
            ])
            ->assertStatus(200);

        $salon->refresh();
        $this->assertTrue($salon->isOnCommissionModel());
        $this->assertEquals(14.0, (float) $salon->commission_percentage);
        $this->assertSame('approved', $request->fresh()->status);
    }

    public function test_every_commission_salon_gets_the_same_plans_benefits(): void
    {
        $plan = $this->givenCommissionPlan();

        [$one, $superAdmin] = $this->fixture();
        [$two] = $this->fixture();

        $commission = app(CommissionService::class);
        $commission->activate($one, 10.0, $superAdmin);
        $commission->activate($two, 22.0, $superAdmin);

        $this->assertSame($plan->id, $one->fresh()->currentSubscription->plan_id);
        $this->assertSame($plan->id, $two->fresh()->currentSubscription->plan_id);
        // Same benefits, different rates — which is the whole point.
        $this->assertEquals(10.0, (float) $one->fresh()->commission_percentage);
        $this->assertEquals(22.0, (float) $two->fresh()->commission_percentage);
    }

    /**
     * The plan carrying the Commission Model is still an ordinary plan.
     *
     * A salon may buy it outright — that just means paying up front instead of
     * a percentage, and it moves them onto the Subscription Plan model.
     */
    public function test_the_commission_plan_is_still_an_ordinary_plan_a_salon_can_buy(): void
    {
        $plan = $this->givenCommissionPlan();
        [$salon] = $this->fixture();
        $this->onCommissionModel($salon, 10.0);
        $owner = User::find($salon->admin_id);

        $listed = $this->actingAs($owner, 'sanctum')
            ->getJson('/api/partner/subscription/plans')
            ->assertStatus(200)
            ->json();

        $this->assertContains($plan->id, collect($listed['plans'])->pluck('id')->all());
        $this->assertTrue($listed['commission_model']['available']);

        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/subscription/upgrade", ['plan_id' => $plan->id])
            ->assertStatus(200);

        // Buying is leaving the Commission Model, so they now pay up front.
        $salon->refresh();
        $this->assertFalse($salon->isOnCommissionModel());
        $this->assertSame(BillingModel::SUBSCRIPTION, $salon->currentSubscription->billing_type);
    }

    public function test_buying_a_plan_leaves_the_commission_model_and_closes_the_rate(): void
    {
        [$salon, $superAdmin] = $this->fixture();
        $this->onCommissionModel($salon, 12.0);

        $plan = SubscriptionPlan::purchasable()->first();

        if (! $plan) {
            $this->markTestSkipped('needs a purchasable plan');
        }

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson("/api/superadmin/salons/{$salon->id}/subscription", [
                'billing_type' => BillingModel::SUBSCRIPTION,
                'plan_id' => $plan->id,
            ])
            ->assertStatus(200);

        $salon->refresh();
        $this->assertFalse($salon->isOnCommissionModel());
        $this->assertNull($salon->commission_percentage);
        $this->assertSame(BillingModel::SUBSCRIPTION, $salon->currentSubscription->billing_type);

        // History survives, because settled payouts still refer to it.
        $this->assertSame(1, SalonCommissionRate::where('salon_id', $salon->id)->count());
        $this->assertNotNull(SalonCommissionRate::where('salon_id', $salon->id)->first()->effective_to);
    }

    public function test_a_commission_salon_has_nothing_to_renew(): void
    {
        [$salon] = $this->fixture();
        $this->onCommissionModel($salon, 10.0);

        $this->actingAs(User::find($salon->admin_id), 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/subscription/renew")
            ->assertStatus(422)
            ->assertJsonPath('success', false);
    }

    // ----------------------------------------------------------------- setup

    private function givenCommissionPlan(): SubscriptionPlan
    {
        $plan = SubscriptionPlan::commissionPlan()
            ?? SubscriptionPlan::where('is_commission_plan', false)->orderByDesc('price')->first();

        if (! $plan) {
            $this->markTestSkipped('needs a subscription plan');
        }

        return app(CommissionService::class)->setPlan($plan);
    }

    private function onCommissionModel(Salon $salon, float $rate): void
    {
        $this->givenCommissionPlan();

        app(CommissionService::class)->activate(
            $salon,
            $rate,
            User::where('role', 'superadmin')->first() ?? User::first()
        );

        $salon->refresh();
    }

    private function onSubscriptionPlan(Salon $salon): void
    {
        $plan = SubscriptionPlan::purchasable()->first() ?? SubscriptionPlan::first();

        if (! $plan) {
            $this->markTestSkipped('needs a subscription plan');
        }

        SalonSubscription::where('salon_id', $salon->id)->update(['status' => 'cancelled']);

        $salon->forceFill([
            'commission_opt_in' => false,
            'commission_percentage' => null,
            'commission_rate_effective_from' => null,
        ])->save();

        SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'billing_type' => BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => $plan->price,
            'start_date' => Carbon::today()->subDay(),
            'end_date' => Carbon::today()->addDays(30),
            'status' => 'active',
        ]);

        $salon->refresh();
    }

    /** @return array{0: Carbon, 1: Carbon} */
    private function thisMonth(): array
    {
        $start = Carbon::today()->startOfMonth();

        return [$start, $start->copy()->endOfMonth()];
    }

    /** @return array{0: Salon, 1: User, 2: ServiceProvider} */
    private function fixture(): array
    {
        $superAdmin = User::where('role', 'superadmin')->first() ?? User::where('role', 'admin')->first();

        if (! $superAdmin) {
            $this->markTestSkipped('needs an elevated account');
        }

        $unique = substr(bin2hex(random_bytes(6)), 0, 10);

        $admin = User::create([
            'name' => "Billing Admin {$unique}",
            'phone' => '9' . substr((string) crc32($unique), 0, 9),
            'password_hash' => 'x',
            'role' => 'admin',
            'is_active' => true,
        ]);

        $salon = Salon::create([
            'admin_id' => $admin->id,
            'name' => "Billing Salon {$unique}",
            'slug' => "billing-salon-{$unique}",
            'address' => 'Test address',
            'submitted_by' => $admin->id,
            'status' => 'active',
        ]);

        $staff = User::create([
            'name' => "Staff {$unique}",
            'phone' => '8' . substr((string) crc32($unique . 'p'), 0, 9),
            'password_hash' => 'x',
            'role' => 'service_provider',
            'is_active' => true,
        ]);

        $provider = ServiceProvider::create([
            'user_id' => $staff->id,
            'salon_id' => $salon->id,
            'base_salary' => 0,
            'commission_percentage' => 0,
            'auto_approve_leave' => false,
            'is_active' => true,
            'joined_at' => Carbon::today()->subYear(),
        ]);

        return [$salon, $superAdmin, $provider];
    }

    private function givenCompleted(
        Salon $salon,
        ServiceProvider $provider,
        float $total,
        float $advance,
        Carbon $on
    ): Appointment {
        return Appointment::create([
            'salon_id' => $salon->id,
            'appointed_provider_id' => $provider->id,
            'serving_provider_id' => $provider->id,
            'booking_source' => 'online',
            'appointment_date' => $on->toDateString(),
            'start_time' => '10:00:00',
            'end_time' => '10:30:00',
            'status' => 'completed',
            'payment_option' => 'advance_only',
            'total_amount' => $total,
            'advance_amount' => $advance,
            'balance_amount' => $total - $advance,
            'completed_at' => now(),
        ]);
    }
}
