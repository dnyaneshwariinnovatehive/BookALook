<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\InvoiceSetting;
use App\Models\SettlementInvoice;
use App\Models\Salon;
use App\Models\SalonCommissionRate;
use App\Models\SalonPayout;
use App\Models\SalonSubscription;
use App\Models\ServiceProvider;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Services\PayoutService;
use App\Support\BillingModel;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * The settlement statement a salon owner is given when a cycle of money is paid.
 *
 * Three things are being defended here:
 *
 *  1. It exists only once the money has actually moved. A cycle that has been
 *     calculated or approved but not distributed is still a promise, and
 *     issuing a document for a promise is how a salon ends up with two.
 *  2. It is one per payout. markDistributed() is guarded against paying twice,
 *     and the document has to be guarded as firmly as the payment.
 *  3. It says the same money the payout does. The line items are a presentation
 *     of the payout's own components rather than a second calculation, and the
 *     totals are frozen at that instant.
 *
 * Runs inside a transaction so it can use the development database without
 * leaving anything behind.
 */
class SettlementInvoiceTest extends TestCase
{
    use DatabaseTransactions;

    public function test_distributing_a_payout_issues_a_settlement_invoice(): void
    {
        [$salon, $superAdmin, $provider] = $this->commissionFixture(rate: 20.0);

        [$start, $end] = $this->thisMonth();
        $this->givenCompleted($salon, $provider, total: 1000, advance: 400, on: $start);

        $payout = app(PayoutService::class)->calculate($salon->id, $start, $end);

        // Calculated and approved is not settled. Nothing has been paid yet, so
        // there is nothing to state.
        $this->assertSame(0, SettlementInvoice::where('payout_id', $payout->id)->count());

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$payout->id}/approve")
            ->assertStatus(200);

        $this->assertSame(0, SettlementInvoice::where('payout_id', $payout->id)->count());

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$payout->id}/distribute", [
                'distribution_reference' => 'NEFT-12345',
            ])
            ->assertStatus(200);

        $invoice = SettlementInvoice::where('payout_id', $payout->id)->firstOrFail();

        $this->assertSame('INR', $invoice->currency);
        $this->assertNotEmpty($invoice->invoice_number);
        $this->assertSame('NEFT-12345', $invoice->distribution_reference);
        $this->assertNotNull($invoice->paid_at);

        // The statement repeats the payout's own figures rather than its own.
        $payout->refresh();
        $this->assertEquals((float) $payout->gross_amount, $invoice->advances_held);
        $this->assertEquals((float) $payout->commission_deducted, $invoice->commission_deducted);
        $this->assertEquals((float) $payout->net_amount, $invoice->net_amount);
        $this->assertEquals(20.0, $invoice->commission_percentage);
    }

    public function test_the_settlement_number_runs_on_its_own_series(): void
    {
        [$salon, $superAdmin, $provider] = $this->commissionFixture(rate: 10.0);

        InvoiceSetting::updateOrCreate(
            ['setting_key' => 'settlement_invoice_number_prefix'],
            ['setting_value' => 'PAY', 'data_type' => 'string']
        );
        InvoiceSetting::updateOrCreate(
            ['setting_key' => 'settlement_invoice_number_padding'],
            ['setting_value' => '4', 'data_type' => 'integer']
        );

        $customerCounterBefore = InvoiceSetting::value('invoice_number_seq_' . now()->format('Y'));

        [$start, $end] = $this->thisMonth();
        $this->givenCompleted($salon, $provider, total: 2000, advance: 900, on: $start);

        $payout = app(PayoutService::class)->calculate($salon->id, $start, $end);

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$payout->id}/distribute")
            ->assertStatus(200);

        $invoice = SettlementInvoice::where('payout_id', $payout->id)->firstOrFail();

        $this->assertMatchesRegularExpression(
            '/^PAY-' . now()->format('Y') . '-\d{4}$/',
            $invoice->invoice_number
        );

        // Its own counter, so a settlement can never be mistaken for a customer
        // receipt — and settling a week of money does not consume a number an
        // invoice would later have used.
        $this->assertSame(
            $customerCounterBefore,
            InvoiceSetting::value('invoice_number_seq_' . now()->format('Y'))
        );
        $this->assertSame(
            1,
            (int) InvoiceSetting::value('settlement_invoice_number_seq_' . now()->format('Y'))
        );
    }

    public function test_the_line_items_add_up_to_the_net_paid(): void
    {
        [$salon, $superAdmin, $provider] = $this->commissionFixture(rate: 25.0);

        [$start, $end] = $this->thisMonth();
        // The advance has to exceed the commission, or the net comes to zero —
        // and a cycle that settles nothing is deliberately not issued a
        // statement at all (see test_a_cycle_that_settles_nothing_is_not_stated).
        // 1800 held less 1000 commission leaves 800 actually paid.
        $this->givenCompleted($salon, $provider, total: 4000, advance: 1800, on: $start);

        $payout = app(PayoutService::class)->calculate($salon->id, $start, $end);

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$payout->id}/distribute")
            ->assertStatus(200);

        $invoice = SettlementInvoice::where('payout_id', $payout->id)->firstOrFail();

        $sum = collect($invoice->line_items)->sum(fn (array $line) => (float) $line['amount']);

        $this->assertEquals((float) $invoice->net_amount, round($sum, 2));
        $this->assertEquals(800.0, (float) $invoice->net_amount);

        // The commission is a deduction, so it is negative on the statement. An
        // owner reading the document has to see at a glance which way each row
        // moves the total.
        $commission = collect($invoice->line_items)->first(
            fn (array $line) => str_starts_with($line['name'], 'Commission')
        );

        $this->assertNotNull($commission);
        $this->assertEquals(-1000.0, (float) $commission['amount']);
    }

    /**
     * A quiet week — commission and commission offsetting exactly — settles
     * nothing, so there is no document.
     *
     * Issuing one would hand an owner a statement for money that never moved,
     * which is worse than issuing nothing: a numbered document in the series
     * that says the salon was paid zero is a thing someone has to explain.
     */
    public function test_a_cycle_that_settles_nothing_is_not_stated(): void
    {
        [$salon, $superAdmin, $provider] = $this->commissionFixture(rate: 25.0);

        [$start, $end] = $this->thisMonth();
        // 1000 billed, 25% commission, 1000 of advances held: net exactly zero.
        $this->givenCompleted($salon, $provider, total: 4000, advance: 1000, on: $start);

        $payout = app(PayoutService::class)->calculate($salon->id, $start, $end);

        $this->assertEquals(0.0, (float) $payout->net_amount);

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$payout->id}/distribute")
            ->assertStatus(200);

        $this->assertSame(0, SettlementInvoice::where('payout_id', $payout->id)->count());
    }

    public function test_a_subscription_salon_gets_a_statement_with_no_commission_row(): void
    {
        [$salon, $superAdmin, $provider] = $this->commissionFixture();

        $this->givenSubscription($salon, BillingModel::SUBSCRIPTION);

        [$weekStart, $weekEnd] = $this->thisWeek();
        $this->givenCompleted($salon, $provider, total: 4000, advance: 1000, on: $weekStart);

        $payout = app(PayoutService::class)->calculate($salon->id, $weekStart, $weekEnd);

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$payout->id}/distribute")
            ->assertStatus(200);

        $invoice = SettlementInvoice::where('payout_id', $payout->id)->firstOrFail();

        $this->assertSame(0.0, $invoice->commission_deducted);
        $this->assertSame(
            0,
            collect($invoice->line_items)->filter(fn ($l) => str_starts_with($l['name'], 'Commission'))->count(),
            'a plan salon has no commission to explain, so it should not be shown one'
        );
        $this->assertSame('weekly', $invoice->cycle_type);
    }

    public function test_a_second_distribution_attempt_cannot_issue_a_second_invoice(): void
    {
        [$salon, $superAdmin, $provider] = $this->commissionFixture(rate: 10.0);

        [$start, $end] = $this->thisMonth();
        $this->givenCompleted($salon, $provider, total: 1000, advance: 500, on: $start);

        $payout = app(PayoutService::class)->calculate($salon->id, $start, $end);

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$payout->id}/distribute")
            ->assertStatus(200);

        $first = SettlementInvoice::where('payout_id', $payout->id)->firstOrFail()->invoice_number;

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$payout->id}/distribute")
            ->assertStatus(422);

        $this->assertSame(1, SettlementInvoice::where('payout_id', $payout->id)->count());
        $this->assertSame(
            $first,
            SettlementInvoice::where('payout_id', $payout->id)->firstOrFail()->invoice_number
        );
    }

    public function test_the_settlement_link_works_without_a_bearer_token(): void
    {
        [$salon, $superAdmin, $provider] = $this->commissionFixture(rate: 10.0);

        [$start, $end] = $this->thisMonth();
        $this->givenCompleted($salon, $provider, total: 1000, advance: 400, on: $start);

        $payout = app(PayoutService::class)->calculate($salon->id, $start, $end);

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$payout->id}/distribute")
            ->assertStatus(200);

        $admin = User::findOrFail($salon->admin_id);

        $url = $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/payouts")
            ->assertStatus(200)
            ->json('payouts.0.settlement_invoice.url');

        $this->assertNotEmpty($url);

        // The owner opens this in the phone's browser, which cannot present a
        // token — the signature is the only proof, which is the point.
        $this->get($url)->assertStatus(200)->assertSee('Settlement Invoice', false);

        // Someone swapped the id out for another salon's.
        $this->get(str_replace('signature=', 'signature=' . str_repeat('0', 5), $url))
            ->assertStatus(403);
    }

    public function test_a_settlement_keeps_the_format_it_was_issued_with(): void
    {
        [$salon, $superAdmin, $provider] = $this->commissionFixture(rate: 10.0);

        [$start, $end] = $this->thisMonth();
        $this->givenCompleted($salon, $provider, total: 1000, advance: 400, on: $start);

        $payout = app(PayoutService::class)->calculate($salon->id, $start, $end);

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$payout->id}/distribute")
            ->assertStatus(200);

        $invoice = SettlementInvoice::where('payout_id', $payout->id)->firstOrFail();

        $this->assertSame('BookALook', $invoice->template['invoice_business_name']);

        InvoiceSetting::updateOrCreate(
            ['setting_key' => 'invoice_business_name'],
            ['setting_value' => 'Renamed Platform', 'data_type' => 'string']
        );

        // A later rebrand must not rewrite a document the owner has filed.
        $this->assertSame(
            'BookALook',
            SettlementInvoice::findOrFail($invoice->id)->template['invoice_business_name']
        );
    }

    // ------------------------------------------------------------- fixtures

    /** @return array{0: Salon, 1: User, 2: ServiceProvider} */
    private function commissionFixture(?float $rate = 10.0): array
    {
        $superAdmin = User::where('role', 'superadmin')->first() ?? User::where('role', 'admin')->first();

        if (! $superAdmin) {
            $this->markTestSkipped('needs an elevated account');
        }

        $unique = substr(bin2hex(random_bytes(6)), 0, 10);

        $admin = User::create([
            'name' => "Settlement Admin {$unique}",
            'phone' => '9' . substr((string) crc32($unique), 0, 9),
            'password_hash' => 'x',
            'role' => 'admin',
            'is_active' => true,
        ]);

        $salon = Salon::create([
            'admin_id' => $admin->id,
            'name' => "Settlement Salon {$unique}",
            'slug' => "settlement-salon-{$unique}",
            'address' => 'Test address',
            'phone_num' => '9876543210',
            'submitted_by' => $admin->id,
            'status' => 'active',
        ]);

        $this->givenSubscription($salon, BillingModel::COMMISSION, $rate);

        $provider = User::create([
            'name' => "Settlement Staff {$unique}",
            'phone' => '8' . substr((string) crc32('staff' . $unique), 0, 9),
            'password_hash' => 'x',
            'role' => 'service_provider',
            'is_active' => true,
        ]);

        return [
            $salon,
            $superAdmin,
            ServiceProvider::create([
                'user_id' => $provider->id,
                'salon_id' => $salon->id,
                'base_salary' => 0,
                'commission_percentage' => 0,
                'auto_approve_leave' => false,
                'is_active' => true,
                'joined_at' => Carbon::today()->subYear(),
            ]),
        ];
    }

    private function givenSubscription(Salon $salon, string $billingType, ?float $rate = null): void
    {
        SalonSubscription::where('salon_id', $salon->id)->update(['status' => 'cancelled']);

        $plan = SubscriptionPlan::first();

        if (! $plan) {
            $this->markTestSkipped('needs a subscription plan');
        }

        $isCommission = BillingModel::isCommission($billingType);

        $salon->forceFill([
            'commission_opt_in' => $isCommission,
            'commission_percentage' => $isCommission ? $rate : null,
            'commission_rate_effective_from' => $isCommission ? Carbon::today()->subDay() : null,
        ])->save();

        if ($isCommission) {
            SalonCommissionRate::where('salon_id', $salon->id)->update(['effective_to' => Carbon::yesterday()]);
            SalonCommissionRate::create([
                'salon_id' => $salon->id,
                'percentage' => $rate ?? 0,
                'effective_from' => Carbon::today()->subDay(),
            ]);
        }

        SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'billing_type' => $billingType,
            'commission_percentage' => $rate,
            'plan_price_snapshot' => $plan->price,
            'start_date' => Carbon::today()->subDays(1),
            'end_date' => Carbon::today()->addDays(30),
            'status' => 'active',
        ]);
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

    /** @return array{0: Carbon, 1: Carbon} */
    private function thisWeek(): array
    {
        $start = Carbon::today()->startOfWeek();

        return [$start, $start->copy()->endOfWeek()];
    }

    /** @return array{0: Carbon, 1: Carbon} */
    private function thisMonth(): array
    {
        $start = Carbon::today()->startOfMonth();

        return [$start, $start->copy()->endOfMonth()];
    }
}
