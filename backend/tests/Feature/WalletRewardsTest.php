<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\PlatformPolicySetting;
use App\Models\Salon;
use App\Models\SalonPayout;
use App\Models\SalonSubscription;
use App\Models\SalonWallet;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Models\WalletScheme;
use App\Models\WalletTransaction;
use App\Services\WalletService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * The salon rewards wallet: earning against a ladder, and the only two ways
 * coins can leave it.
 *
 * Runs in a transaction so it can use the development database without
 * leaving anything behind.
 */
class WalletRewardsTest extends TestCase
{
    use DatabaseTransactions;

    public function test_a_ladder_pays_more_as_the_salon_climbs_it(): void
    {
        [$salon, $superAdmin] = $this->fixture();
        $this->setCoinValue(2.50);

        $scheme = $this->givenLadder($superAdmin, [
            ['appointments_from' => 1, 'appointments_to' => 3, 'coins_awarded' => 1],
            ['appointments_from' => 4, 'appointments_to' => 5, 'coins_awarded' => 5],
            ['appointments_from' => 6, 'appointments_to' => null, 'coins_awarded' => 10],
        ]);

        $wallet = app(WalletService::class);
        $this->resetWallet($salon);

        $earned = [];
        for ($i = 0; $i < 7; $i++) {
            $earned[] = $wallet->awardForCompletedAppointment($this->givenCompleted($salon))['coins_earned'];
        }

        // Three at 1, two at 5, then the open-ended rung at 10.
        $this->assertSame([1, 1, 1, 5, 5, 10, 10], $earned);
        $this->assertSame(33, (int) SalonWallet::find($salon->id)->coin_balance);

        // Each award explains which rung produced it and what a coin was worth.
        $first = WalletTransaction::where('salon_id', $salon->id)
            ->where('type', WalletTransaction::TYPE_EARNED)
            ->orderBy('created_at')
            ->first();

        $this->assertNotNull($first->related_scheme_tier_id);
        $this->assertNotNull($first->related_appointment_id);
        $this->assertEquals(2.50, (float) $first->coin_value_snapshot);
        $this->assertSame(1, (int) $first->balance_after);
        $this->assertStringContainsString($scheme->name, $first->note);
    }

    public function test_a_completion_scheme_pays_a_lump_when_the_band_finishes(): void
    {
        [$salon, $superAdmin] = $this->fixture();
        $this->setCoinValue(1.0);

        $this->givenLadder($superAdmin, [
            ['appointments_from' => 1, 'appointments_to' => 3, 'coins_awarded' => 30],
            ['appointments_from' => 4, 'appointments_to' => null, 'coins_awarded' => 99],
        ], WalletScheme::MODE_ON_COMPLETION);

        $wallet = app(WalletService::class);
        $this->resetWallet($salon);

        $earned = [];
        for ($i = 0; $i < 5; $i++) {
            $earned[] = $wallet->awardForCompletedAppointment($this->givenCompleted($salon))['coins_earned'];
        }

        // Only the third appointment closes the first band; the open-ended rung
        // never completes, so it never pays a lump.
        $this->assertSame([0, 0, 30, 0, 0], $earned);
    }

    public function test_walk_ins_do_not_earn_and_awards_are_not_repeated(): void
    {
        [$salon, $superAdmin] = $this->fixture();
        $this->setCoinValue(1.0);
        $this->givenLadder($superAdmin, [
            ['appointments_from' => 1, 'appointments_to' => null, 'coins_awarded' => 5],
        ]);

        $wallet = app(WalletService::class);
        $this->resetWallet($salon);

        // A walk-in is the salon's own customer, not one the platform brought.
        $walkIn = $this->givenCompleted($salon, source: 'walk_in');
        $this->assertSame(0, $wallet->awardForCompletedAppointment($walkIn)['coins_earned']);

        $online = $this->givenCompleted($salon);
        $this->assertSame(5, $wallet->awardForCompletedAppointment($online)['coins_earned']);
        // A retried completion must not mint coins twice.
        $this->assertSame(0, $wallet->awardForCompletedAppointment($online)['coins_earned']);

        $this->assertSame(5, (int) SalonWallet::find($salon->id)->coin_balance);
    }

    public function test_coins_settle_against_commission_only_on_a_commission_plan(): void
    {
        [$salon, , $admin] = $this->fixture();
        $this->setCoinValue(10.0);
        $this->giveCoins($salon, 50);

        $payout = SalonPayout::create([
            'salon_id' => $salon->id,
            'cycle_start_date' => Carbon::today()->subDays(7),
            'cycle_end_date' => Carbon::today(),
            'gross_amount' => 5000,
            'commission_deducted' => 400,
            'net_amount' => 4600,
            'status' => 'pending',
        ]);

        // Flat plan: there is no commission relationship to settle.
        $this->givenSubscription($salon, \App\Support\BillingModel::SUBSCRIPTION);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/wallet/redeem-commission", [
                'payout_id' => $payout->id,
                'coins_to_redeem' => 10,
            ])
            ->assertStatus(422)
            ->assertJsonPath('message', 'Coins can only be settled against commission on a Commission Model.');

        $this->givenSubscription($salon, \App\Support\BillingModel::COMMISSION);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/wallet/redeem-commission", [
                'payout_id' => $payout->id,
                'coins_to_redeem' => 10,
            ])
            ->assertStatus(200)
            ->assertJsonPath('coins_redeemed', 10)
            ->assertJsonPath('new_balance', 40)
            // JSON drops the trailing .0, so compare loosely.
            ->assertJson(fn ($json) => $json->where('discount_applied', fn ($v) => (float) $v === 100.0)
                ->etc());

        $payout->refresh();
        $this->assertEquals(100.0, (float) $payout->wallet_redeemed_amount);
        $this->assertEquals(4700.0, (float) $payout->net_amount);

        $entry = WalletTransaction::where('salon_id', $salon->id)
            ->where('type', WalletTransaction::TYPE_REDEEMED)
            ->latest('created_at')
            ->first();

        $this->assertSame(-10, (int) $entry->coins);
        $this->assertSame($payout->id, $entry->related_payout_id);
        $this->assertSame($admin->id, $entry->created_by);
    }

    public function test_coins_cannot_be_burnt_beyond_what_the_bill_is_worth(): void
    {
        [$salon, , $admin] = $this->fixture();
        $this->setCoinValue(10.0);
        $this->giveCoins($salon, 500);
        $this->givenSubscription($salon, \App\Support\BillingModel::COMMISSION);

        $payout = SalonPayout::create([
            'salon_id' => $salon->id,
            'cycle_start_date' => Carbon::today()->subDays(7),
            'cycle_end_date' => Carbon::today(),
            'gross_amount' => 1000,
            'commission_deducted' => 50, // only 5 coins' worth
            'net_amount' => 950,
            'status' => 'pending',
        ]);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/wallet/redeem-commission", [
                'payout_id' => $payout->id,
                'coins_to_redeem' => 40,
            ])
            ->assertStatus(422);

        // Untouched — a rejected redemption must not move the balance.
        $this->assertSame(500, (int) SalonWallet::find($salon->id)->coin_balance);
    }

    public function test_coins_apply_to_a_subscription_purchase(): void
    {
        [$salon, , $admin] = $this->fixture();
        $this->setCoinValue(10.0);
        $this->giveCoins($salon, 30);

        $plan = SubscriptionPlan::first();

        if (! $plan) {
            $this->markTestSkipped('needs a subscription plan');
        }

        $quote = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/wallet/quote", ['plan_id' => $plan->id])
            ->assertStatus(200)
            ->json();

        $this->assertLessThanOrEqual(30, $quote['coins_usable']);
        $this->assertEquals(
            round($quote['bill_amount'] - $quote['discount_value'], 2),
            $quote['payable_after_coins']
        );

        $response = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/subscription/upgrade", [
                'plan_id' => $plan->id,
                'apply_coins' => true,
            ])
            ->assertStatus(200)
            ->json();

        $this->assertSame($quote['coins_usable'], $response['coins_redeemed']);
        $this->assertEquals($quote['payable_after_coins'], $response['amount_payable']);

        $this->assertSame(
            30 - $quote['coins_usable'],
            (int) SalonWallet::find($salon->id)->coin_balance
        );

        // The redemption points at the subscription it paid for.
        $entry = WalletTransaction::where('salon_id', $salon->id)
            ->where('type', WalletTransaction::TYPE_REDEEMED)
            ->latest('created_at')
            ->first();
        $this->assertNotNull($entry->related_subscription_id);
    }

    public function test_the_wallet_shows_balance_progress_and_both_histories(): void
    {
        [$salon, $superAdmin, $admin] = $this->fixture();
        $this->setCoinValue(4.0);
        $this->givenLadder($superAdmin, [
            ['appointments_from' => 1, 'appointments_to' => 2, 'coins_awarded' => 3],
            ['appointments_from' => 3, 'appointments_to' => null, 'coins_awarded' => 9],
        ]);

        $this->resetWallet($salon);
        $wallet = app(WalletService::class);
        $wallet->awardForCompletedAppointment($this->givenCompleted($salon));

        $body = $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/wallet")
            ->assertStatus(200)
            ->json();

        $this->assertSame(3, $body['balance']);
        $this->assertEquals(4.0, $body['coin_value_inr']);
        $this->assertEquals(12.0, $body['balance_value_inr']);
        $this->assertCount(1, $body['earned']);
        $this->assertCount(0, $body['redeemed']);
        $this->assertNotNull($body['earned'][0]['tier_label']);

        // Where they are on the ladder, and what the next rung is worth.
        $this->assertSame(1, $body['progress']['completed_online_appointments']);
        $this->assertSame(3, $body['progress']['current_tier']['coins_awarded']);
        $this->assertSame(9, $body['progress']['next_tier']['coins_awarded']);
        $this->assertSame(2, $body['progress']['appointments_to_next_tier']);
    }

    public function test_superadmin_rejects_a_ladder_with_a_gap(): void
    {
        [, $superAdmin] = $this->fixture();

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson('/api/superadmin/wallet-schemes', [
                'name' => 'Broken ladder',
                'tiers' => [
                    ['appointments_from' => 1, 'appointments_to' => 250, 'coins_awarded' => 1],
                    // 251 is missing.
                    ['appointments_from' => 300, 'appointments_to' => null, 'coins_awarded' => 3],
                ],
            ])
            ->assertStatus(422);

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson('/api/superadmin/wallet-schemes', [
                'name' => 'Does not start at one',
                'tiers' => [
                    ['appointments_from' => 10, 'appointments_to' => null, 'coins_awarded' => 1],
                ],
            ])
            ->assertStatus(422);
    }

    public function test_the_newest_active_scheme_supersedes_older_ones(): void
    {
        [$salon, $superAdmin] = $this->fixture();
        $this->setCoinValue(1.0);

        $this->givenLadder($superAdmin, [
            ['appointments_from' => 1, 'appointments_to' => null, 'coins_awarded' => 2],
        ], name: 'Old ladder');

        $newer = $this->givenLadder($superAdmin, [
            ['appointments_from' => 1, 'appointments_to' => null, 'coins_awarded' => 7],
        ], name: 'New ladder');

        $this->resetWallet($salon);

        $this->assertSame($newer->id, app(WalletService::class)->schemeInForceOn()->id);
        $this->assertSame(
            7,
            app(WalletService::class)->awardForCompletedAppointment($this->givenCompleted($salon))['coins_earned']
        );
    }

    public function test_a_scheme_that_has_paid_coins_is_closed_rather_than_deleted(): void
    {
        [$salon, $superAdmin] = $this->fixture();
        $this->setCoinValue(1.0);

        $scheme = $this->givenLadder($superAdmin, [
            ['appointments_from' => 1, 'appointments_to' => null, 'coins_awarded' => 4],
        ]);

        $this->resetWallet($salon);
        app(WalletService::class)->awardForCompletedAppointment($this->givenCompleted($salon));

        $this->actingAs($superAdmin, 'sanctum')
            ->deleteJson("/api/superadmin/wallet-schemes/{$scheme->id}")
            ->assertStatus(200)
            ->assertJsonPath('deactivated', true);

        // Still there, so the history that points at its rungs still resolves.
        $this->assertDatabaseHas('wallet_schemes', ['id' => $scheme->id, 'is_active' => false]);
    }

    public function test_only_the_salon_owner_can_use_the_wallet(): void
    {
        [$salon] = $this->fixture();
        $customer = User::where('role', 'customer')->first();

        $this->actingAs($customer, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/wallet")
            ->assertStatus(403);
    }

    // ------------------------------------------------------------- fixtures

    /** @return array{0: Salon, 1: User, 2: User} */
    private function fixture(): array
    {
        // Needs a provider too, since earning is driven by completed appointments.
        $salon = Salon::whereNotNull('admin_id')
            ->whereHas('providers')
            ->first();
        $superAdmin = User::where('role', 'superadmin')->first() ?? User::where('role', 'admin')->first();

        if (! $salon || ! $superAdmin) {
            $this->markTestSkipped('needs a salon with an owner and an elevated account');
        }

        return [$salon, $superAdmin, User::find($salon->admin_id)];
    }

    private function setCoinValue(float $value): void
    {
        PlatformPolicySetting::updateOrCreate(
            ['setting_key' => WalletService::COIN_VALUE_KEY],
            [
                'setting_value' => (string) $value,
                'data_type' => 'decimal',
                'updated_by' => User::query()->value('id'),
            ]
        );
    }

    /** @param array<int, array> $tiers */
    private function givenLadder(
        User $creator,
        array $tiers,
        string $mode = WalletScheme::MODE_PER_APPOINTMENT,
        string $name = 'Test ladder'
    ): WalletScheme {
        // Retire anything already published so the test controls what is in force.
        WalletScheme::query()->update(['is_active' => false]);

        $scheme = WalletScheme::create([
            'name' => $name,
            'award_mode' => $mode,
            'is_active' => true,
            'created_by' => $creator->id,
        ]);

        foreach ($tiers as $index => $tier) {
            $scheme->tiers()->create([
                'tier_order' => $index + 1,
                'appointments_from' => $tier['appointments_from'],
                'appointments_to' => $tier['appointments_to'],
                'appointments_required' => $tier['appointments_from'],
                'coins_awarded' => $tier['coins_awarded'],
            ]);
        }

        return $scheme->fresh('tiers');
    }

    private function resetWallet(Salon $salon): void
    {
        SalonWallet::updateOrCreate(
            ['salon_id' => $salon->id],
            ['coin_balance' => 0, 'completed_online_appointments_count' => 0]
        );
    }

    private function giveCoins(Salon $salon, int $coins): void
    {
        SalonWallet::updateOrCreate(
            ['salon_id' => $salon->id],
            ['coin_balance' => $coins, 'completed_online_appointments_count' => 0]
        );
    }

    private function givenSubscription(Salon $salon, string $billingType): void
    {
        SalonSubscription::where('salon_id', $salon->id)->update(['status' => 'cancelled']);

        $plan = SubscriptionPlan::first();

        if (! $plan) {
            $this->markTestSkipped('needs a subscription plan');
        }

        // Which arrangement a salon is on is the salon's own flag; coins may
        // only be settled against commission when there is commission to owe.
        $salon->forceFill([
            'commission_opt_in' => \App\Support\BillingModel::isCommission($billingType),
        ])->save();

        SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'billing_type' => $billingType,
            'plan_price_snapshot' => $plan->price,
            'start_date' => Carbon::today(),
            'end_date' => Carbon::today()->addDays(30),
            'status' => 'active',
        ]);
    }

    private function givenCompleted(Salon $salon, string $source = 'online'): Appointment
    {
        $provider = \App\Models\ServiceProvider::where('salon_id', $salon->id)->first();

        if (! $provider) {
            $this->markTestSkipped('needs a provider at the salon');
        }

        return Appointment::create([
            'salon_id' => $salon->id,
            'appointed_provider_id' => $provider->id,
            'booking_source' => $source,
            'appointment_date' => Carbon::today()->toDateString(),
            'start_time' => '10:00:00',
            'end_time' => '10:30:00',
            'status' => 'completed',
            'payment_option' => 'advance_only',
            'total_amount' => 500,
            'advance_amount' => 0,
            'balance_amount' => 500,
        ]);
    }
}
