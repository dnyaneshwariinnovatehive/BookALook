<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\AuditLog;
use App\Models\Notification;
use App\Models\Salon;
use App\Models\SalonPayout;
use App\Models\ServiceProvider;
use App\Models\User;
use App\Services\PayoutService;
use App\Support\PayoutCycle;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * SuperAdmin's payout desk: the breakdown behind each payout, where to send
 * the money, who did what, the cross-cycle inbox, the overview, search and
 * filters, the CSV export, and telling the salon when it has been paid.
 */
class PayoutDeskTest extends TestCase
{
    use DatabaseTransactions;

    private User $superadmin;

    private string $u;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-11-05 10:00:00');
        $this->u = substr(bin2hex(random_bytes(6)), 0, 8);
        $this->superadmin = User::create(['id' => (string) Str::uuid(), 'role' => 'superadmin', 'name' => "Asha {$this->u}", 'phone' => '2'.random_int(100000000, 999999999), 'password_hash' => 'x', 'is_active' => true]);
    }

    private function salon(string $name): array
    {
        $owner = User::create(['id' => (string) Str::uuid(), 'role' => 'admin', 'name' => "Owner {$name}", 'phone' => '2'.random_int(100000000, 999999999), 'password_hash' => 'x', 'is_active' => true]);
        $salon = Salon::create(['admin_id' => $owner->id, 'name' => "{$name} {$this->u}", 'slug' => Str::slug($name).'-'.Str::lower(Str::random(8)), 'address' => 'x', 'status' => 'active', 'submitted_by' => $owner->id]);
        $salon->forceFill([
            'bank_account_holder_name' => "{$name} Owner", 'bank_name' => 'HDFC Bank',
            'bank_account_number' => '50100123456789', 'bank_ifsc' => 'HDFC0001234', 'bank_upi_id' => 'glow@okhdfc',
        ])->save();
        $provider = ServiceProvider::create(['user_id' => $owner->id, 'salon_id' => $salon->id, 'is_active' => true]);

        return [$salon, $owner, $provider];
    }

    /** A completed online booking with an advance BookALook held. */
    private function booking(Salon $salon, ServiceProvider $provider, string $date, float $advance, string $customer = 'Riya'): void
    {
        $c = User::create(['id' => (string) Str::uuid(), 'role' => 'customer', 'name' => "{$customer} {$this->u}", 'phone' => '2'.random_int(100000000, 999999999), 'password_hash' => 'x', 'is_active' => true]);
        $a = Appointment::create([
            'salon_id' => $salon->id, 'customer_id' => $c->id, 'appointed_provider_id' => $provider->id, 'booking_source' => 'online',
            'appointment_date' => $date, 'start_time' => '10:00:00', 'end_time' => '10:30:00', 'status' => 'completed',
            'total_amount' => 1000, 'advance_amount' => $advance, 'balance_amount' => 1000 - $advance,
        ]);
        DB::table('payments')->insert([
            'id' => (string) Str::uuid(), 'appointment_id' => $a->id, 'amount' => $advance,
            'payment_type' => 'advance', 'payment_mode' => 'online', 'gateway' => 'online_gateway',
            'status' => 'success', 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function weekPayout(Salon $salon): SalonPayout
    {
        return app(PayoutService::class)->calculate($salon->id, Carbon::parse('2026-10-26'), Carbon::parse('2026-11-01'), PayoutCycle::WEEKLY);
    }

    private function as()
    {
        return $this->actingAs($this->superadmin, 'sanctum');
    }

    public function test_the_payout_detail_explains_the_amount_and_shows_where_to_pay(): void
    {
        [$salon, , $provider] = $this->salon('Glow');
        $this->booking($salon, $provider, '2026-10-27', 300, 'Riya');
        $this->booking($salon, $provider, '2026-10-29', 200, 'Meera');
        $payout = $this->weekPayout($salon);

        $res = $this->as()->getJson("/api/superadmin/payouts/{$payout->id}")->assertOk();

        $this->assertCount(2, $res->json('items'));
        $this->assertSame("Riya {$this->u}", $res->json('items.0.customer_name'));
        $this->assertSame('2026-10-27', $res->json('items.0.date'));
        $this->assertEquals(300, $res->json('items.0.advance_held'));

        $this->assertSame('HDFC0001234', $res->json('bank_details.ifsc'));
        $this->assertSame('glow@okhdfc', $res->json('bank_details.upi_id'));
        $this->assertSame('6789', $res->json('bank_details.account_number_last4'));
        $this->assertNull($res->json('bank_details.account_number'), 'the full number is never in this response');
        $this->assertStringNotContainsString('50100123456789', $res->getContent());
    }

    public function test_who_approved_and_paid_is_shown_with_the_reference(): void
    {
        [$salon, , $provider] = $this->salon('Glow');
        $this->booking($salon, $provider, '2026-10-27', 300);
        $payout = $this->weekPayout($salon);

        $this->as()->postJson("/api/superadmin/payouts/{$payout->id}/approve")->assertOk();
        $this->as()->postJson("/api/superadmin/payouts/{$payout->id}/distribute", ['distribution_reference' => 'UTR998877'])->assertOk();

        $history = $this->as()->getJson("/api/superadmin/payouts/{$payout->id}")->json('history');
        $this->assertSame([AuditLog::PAYOUT_APPROVED, AuditLog::PAYOUT_DISTRIBUTED], array_column($history, 'action'));
        $this->assertSame("Asha {$this->u}", $history[1]['by']);
        $this->assertSame('UTR998877', $history[1]['reference']);
    }

    public function test_the_salon_is_told_when_it_has_been_paid(): void
    {
        [$salon, $owner, $provider] = $this->salon('Glow');
        $this->booking($salon, $provider, '2026-10-27', 300);
        $payout = $this->weekPayout($salon);
        $this->as()->postJson("/api/superadmin/payouts/{$payout->id}/approve")->assertOk();

        $this->as()->postJson("/api/superadmin/payouts/{$payout->id}/distribute", ['distribution_reference' => 'UTR1'])->assertOk();

        $notice = Notification::where('user_id', $owner->id)->latest()->first();
        $this->assertNotNull($notice);
        $this->assertSame('Payout sent', $notice->title);
        $this->assertStringContainsString('₹300.00', $notice->message);
        $this->assertStringContainsString('UTR1', $notice->message);
    }

    public function test_the_inbox_gathers_what_waits_across_cycles(): void
    {
        [$a, , $pa] = $this->salon('Alpha');
        [$b, , $pb] = $this->salon('Beta');
        $this->booking($a, $pa, '2026-10-27', 300);
        $this->booking($b, $pb, '2026-10-28', 400);
        $pending = $this->weekPayout($a);
        $approved = $this->weekPayout($b);
        $this->as()->postJson("/api/superadmin/payouts/{$approved->id}/approve")->assertOk();

        $res = $this->as()->getJson('/api/superadmin/payouts/inbox')->assertOk();

        $this->assertContains($pending->id, array_column($res->json('to_approve'), 'id'));
        $this->assertContains($approved->id, array_column($res->json('to_pay'), 'id'));
        $this->assertNotContains($approved->id, array_column($res->json('to_approve'), 'id'));
        $row = collect($res->json('to_approve'))->firstWhere('id', $pending->id);
        $this->assertSame(3, $row['waiting_days'], 'waiting since the day after the cycle ended (2 Nov)');
        $this->assertGreaterThanOrEqual(1, $res->json('counts.to_pay'));
    }

    public function test_search_and_filters_narrow_the_cycle(): void
    {
        [$a, , $pa] = $this->salon('Alpha');
        [$b, , $pb] = $this->salon('Beta');
        $this->booking($a, $pa, '2026-10-27', 300);
        $this->booking($b, $pb, '2026-10-28', 400);
        $this->weekPayout($a);
        $this->weekPayout($b);
        $base = '/api/superadmin/payouts?cycle_type=weekly&cycle_start=2026-10-26';

        $found = $this->as()->getJson("{$base}&search=alpha {$this->u}")->assertOk();
        $this->assertSame(["Alpha {$this->u}"], array_column($found->json('payouts'), 'salon_name'));
        $this->assertSame(1, $found->json('totals.salons'), 'totals follow the search');

        $this->assertSame(0, $this->as()->getJson("{$base}&search=alpha {$this->u}&flow=salon_owes")->json('meta.total'));
        $this->assertNotNull($this->as()->getJson($base)->json('last_calculated_at'));
    }

    public function test_the_overview_adds_up_both_rhythms(): void
    {
        [$a, , $pa] = $this->salon('Alpha');
        $this->booking($a, $pa, '2026-10-27', 300);
        $this->weekPayout($a);

        $res = $this->as()->getJson('/api/superadmin/payouts/overview')->assertOk();

        $this->assertGreaterThanOrEqual(300, $res->json('to_pay_salons'));
        $this->assertSame('November 2026', $res->json('month_label'));
    }

    public function test_the_cycle_exports_as_csv_with_formulas_defused(): void
    {
        [$a, , $pa] = $this->salon('=HYPERLINK');
        $this->booking($a, $pa, '2026-10-27', 300);
        $this->weekPayout($a);

        $res = $this->as()->get("/api/superadmin/payouts/export?cycle_type=weekly&cycle_start=2026-10-26&search={$this->u}")->assertOk();
        $csv = $res->streamedContent();

        $this->assertStringContainsString('text/csv', $res->headers->get('Content-Type'));
        $this->assertStringContainsString('Salon,Billing,Cycle', $csv);
        $this->assertStringContainsString("'=HYPERLINK {$this->u}", $csv, 'a salon name starting with = cannot run as a formula');
        $this->assertStringContainsString('300', $csv);
    }

    public function test_only_superadmin_reaches_the_desk(): void
    {
        [, $owner] = $this->salon('Alpha');

        $this->actingAs($owner, 'sanctum')->getJson('/api/superadmin/payouts/inbox')->assertForbidden();
        $this->actingAs($owner, 'sanctum')->get('/api/superadmin/payouts/export')->assertForbidden();
    }
}
