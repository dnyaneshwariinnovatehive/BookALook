<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\Notification;
use App\Models\PayoutPaymentSubmission;
use App\Models\Salon;
use App\Models\SalonCommissionRate;
use App\Models\SalonPayout;
use App\Models\SalonSubscription;
use App\Models\ServiceProvider;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Services\PayoutService;
use App\Support\BillingModel;
use App\Support\PayoutCycle;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * A Commission Model salon whose commission is more than the advances held
 * pays the difference the way it buys a plan: scan BookALook's QR, upload the
 * screenshot, SuperAdmin verifies and marks it paid.
 */
class PayoutDuesTest extends TestCase
{
    use DatabaseTransactions;

    private User $superadmin;
    private User $owner;
    private Salon $salon;
    private ServiceProvider $provider;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('cloudinary');

        $u = substr(bin2hex(random_bytes(6)), 0, 8);
        $this->superadmin = User::create(['id' => (string) Str::uuid(), 'role' => 'superadmin', 'name' => "SA {$u}", 'phone' => '2'.substr((string) crc32($u.'sa'), 0, 9), 'password_hash' => 'x', 'is_active' => true]);
        $this->owner = User::create(['id' => (string) Str::uuid(), 'role' => 'admin', 'name' => "Owner {$u}", 'phone' => '2'.substr((string) crc32($u.'ow'), 0, 9), 'password_hash' => 'x', 'is_active' => true]);
        $this->salon = Salon::create(['admin_id' => $this->owner->id, 'name' => "Dues {$u}", 'slug' => "dues-{$u}", 'address' => 'x', 'status' => 'active', 'submitted_by' => $this->owner->id,
            'commission_opt_in' => true, 'commission_percentage' => 20]);
        SalonCommissionRate::create(['salon_id' => $this->salon->id, 'percentage' => 20, 'effective_from' => '2026-09-01']);
        $this->provider = ServiceProvider::create(['user_id' => $this->owner->id, 'salon_id' => $this->salon->id, 'is_active' => true]);
    }

    /**
     * A real one-pixel PNG. fake()->image() would draw one, but that needs the
     * GD extension, which not every machine running the suite has.
     */
    private function png(): UploadedFile
    {
        return UploadedFile::fake()->createWithContent(
            'paid.png',
            base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')
        );
    }

    /** October: ₹5,000 billed, ₹200 held online, 20% commission — the salon owes ₹800. */
    private function owingPayout(): SalonPayout
    {
        $a = Appointment::create([
            'salon_id' => $this->salon->id, 'appointed_provider_id' => $this->provider->id, 'booking_source' => 'online',
            'appointment_date' => '2026-10-13', 'start_time' => '10:00:00', 'end_time' => '10:30:00',
            'status' => 'completed', 'total_amount' => 5000, 'advance_amount' => 200, 'balance_amount' => 4800,
        ]);
        DB::table('payments')->insert([
            'id' => (string) Str::uuid(), 'appointment_id' => $a->id, 'amount' => 200, 'payment_type' => 'advance',
            'payment_mode' => 'online', 'gateway' => 'razorpay', 'status' => 'success', 'created_at' => now(), 'updated_at' => now(),
        ]);

        [$s, $e] = PayoutCycle::bounds(PayoutCycle::MONTHLY, Carbon::parse('2026-10-01'));

        return app(PayoutService::class)->calculate($this->salon->id, $s, $e, PayoutCycle::MONTHLY);
    }

    private function pay(SalonPayout $payout, array $extra = [])
    {
        return $this->actingAs($this->owner, 'sanctum')->post(
            "/api/partner/salons/{$this->salon->id}/payouts/{$payout->id}/payment",
            ['screenshot' => $this->png()] + $extra,
            ['Accept' => 'application/json']
        );
    }

    public function test_owner_pays_by_screenshot_and_the_payout_freezes(): void
    {
        $payout = $this->owingPayout();
        $this->assertEquals(-800.0, (float) $payout->net_amount);

        $this->pay($payout, ['transaction_id' => 'UTR123', 'note' => 'From business account'])
            ->assertStatus(200)
            ->assertJsonPath('payment_submission.status', 'pending')
            ->assertJsonPath('payment_submission.amount', 800);

        $this->assertNotNull($payout->fresh()->locked_at);

        // A late booking in October no longer moves what they paid against.
        Appointment::create([
            'salon_id' => $this->salon->id, 'appointed_provider_id' => $this->provider->id, 'booking_source' => 'online',
            'appointment_date' => '2026-10-20', 'start_time' => '10:00:00', 'end_time' => '10:30:00',
            'status' => 'completed', 'total_amount' => 1000, 'advance_amount' => 0, 'balance_amount' => 1000,
        ]);
        [$s, $e] = PayoutCycle::bounds(PayoutCycle::MONTHLY, Carbon::parse('2026-10-01'));
        $this->assertEquals(-800.0, (float) app(PayoutService::class)->calculate($this->salon->id, $s, $e, PayoutCycle::MONTHLY)->net_amount);
    }

    public function test_nothing_to_pay_when_bookalook_owes_the_salon(): void
    {
        $this->salon->forceFill(['commission_opt_in' => false])->save();
        SalonCommissionRate::where('salon_id', $this->salon->id)->update(['effective_to' => '2026-09-30']);
        $payout = $this->owingPayout(); // no commission now: BookALook owes ₹200

        $this->pay($payout)->assertStatus(422);
    }

    public function test_one_payment_under_review_at_a_time_and_only_the_owner_pays(): void
    {
        $payout = $this->owingPayout();
        $this->pay($payout)->assertStatus(200);
        $this->pay($payout)->assertStatus(422);

        $stranger = User::create(['id' => (string) Str::uuid(), 'role' => 'admin', 'name' => 'Other', 'phone' => '2'.random_int(100000000, 999999999), 'password_hash' => 'x', 'is_active' => true]);
        $this->actingAs($stranger, 'sanctum')->post(
            "/api/partner/salons/{$this->salon->id}/payouts/{$payout->id}/payment",
            ['screenshot' => $this->png()],
            ['Accept' => 'application/json']
        )->assertStatus(403);
    }

    public function test_superadmin_verifies_and_the_month_is_settled_and_access_renewed(): void
    {
        $plan = SubscriptionPlan::first() ?? SubscriptionPlan::create(['name' => 'Growth Plan', 'price' => 999, 'duration_days' => 30, 'is_active' => true]);
        $sub = SalonSubscription::create([
            'salon_id' => $this->salon->id, 'plan_id' => $plan->id, 'billing_type' => BillingModel::COMMISSION,
            'plan_price_snapshot' => 0, 'start_date' => '2026-10-01', 'end_date' => '2026-10-31', 'status' => 'active',
        ]);

        $payout = $this->owingPayout();
        $submissionId = $this->pay($payout, ['transaction_id' => 'UTR777'])->json('payment_submission.id');

        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$payout->id}/payments/{$submissionId}/approve")
            ->assertStatus(200)
            ->assertJsonPath('payout.status', PayoutService::STATUS_DISTRIBUTED)
            ->assertJsonPath('payout.distribution_reference', 'UTR777');

        $this->assertSame('approved', PayoutPaymentSubmission::find($submissionId)->status);
        $this->assertTrue(Carbon::parse($sub->fresh()->end_date)->gte(Carbon::parse('2026-11-30')));
        $this->assertTrue(Notification::where('user_id', $this->owner->id)->where('title', 'Payment received')->exists());

        // Approving twice is refused.
        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$payout->id}/payments/{$submissionId}/approve")
            ->assertStatus(422);
    }

    public function test_a_declined_payment_tells_the_owner_why_and_they_pay_again(): void
    {
        $payout = $this->owingPayout();
        $first = $this->pay($payout)->json('payment_submission.id');

        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$payout->id}/payments/{$first}/reject", ['reason' => 'Received ₹500 of ₹800'])
            ->assertStatus(200)
            ->assertJsonPath('payout.payment_submission.status', 'rejected')
            ->assertJsonPath('payout.payment_submission.rejection_reason', 'Received ₹500 of ₹800')
            ->assertJsonPath('payout.status', PayoutService::STATUS_PENDING);

        $this->assertTrue(Notification::where('user_id', $this->owner->id)->where('title', 'Payment not verified')->exists());

        // Same amount owed; they can pay again.
        $this->pay($payout)->assertStatus(200)->assertJsonPath('payment_submission.amount', 800);
    }

    public function test_a_reason_is_needed_to_decline_and_only_superadmin_reviews(): void
    {
        $payout = $this->owingPayout();
        $id = $this->pay($payout)->json('payment_submission.id');

        $this->actingAs($this->superadmin, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$payout->id}/payments/{$id}/reject", [])
            ->assertStatus(422);

        $this->actingAs($this->owner, 'sanctum')
            ->postJson("/api/superadmin/payouts/{$payout->id}/payments/{$id}/approve")
            ->assertStatus(403);
    }

    public function test_a_locked_out_salon_can_still_see_and_pay_what_it_owes(): void
    {
        // No active subscription at all: the salon is locked out of the app's features.
        SalonSubscription::where('salon_id', $this->salon->id)->delete();
        $payout = $this->owingPayout();

        $this->actingAs($this->owner, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salon->id}/payouts")
            ->assertStatus(200);

        $this->pay($payout)->assertStatus(200);
    }

    public function test_coins_cannot_change_a_payout_already_paid_against(): void
    {
        $payout = $this->owingPayout();
        $this->pay($payout)->assertStatus(200);

        $this->actingAs($this->owner, 'sanctum')
            ->postJson("/api/partner/salons/{$this->salon->id}/wallet/redeem-commission", ['payout_id' => $payout->id, 'coins_to_redeem' => 5])
            ->assertStatus(422);
    }

    public function test_the_salon_sees_its_payment_status_on_the_payout(): void
    {
        $payout = $this->owingPayout();
        $this->pay($payout, ['transaction_id' => 'UTR9']);

        $row = collect($this->actingAs($this->owner, 'sanctum')
            ->getJson("/api/partner/salons/{$this->salon->id}/payouts")
            ->json('payouts'))->firstWhere('id', $payout->id);

        $this->assertSame('salon_owes', $row['direction']);
        $this->assertTrue($row['locked']);
        $this->assertSame('pending', $row['payment_submission']['status']);
    }

    // ── where to pay ──────────────────────────────────────────────────────

    public function test_superadmin_sets_the_qr_and_upi_and_salons_read_them(): void
    {
        $this->actingAs($this->superadmin, 'sanctum')
            ->post('/api/superadmin/settings/payment-qr', ['qr' => $this->png()], ['Accept' => 'application/json'])
            ->assertStatus(200);

        $this->actingAs($this->superadmin, 'sanctum')
            ->putJson('/api/superadmin/settings/policy', ['payment_upi_id' => 'bookalook@upi', 'payment_payee_name' => 'BookALook'])
            ->assertStatus(200);

        $details = $this->actingAs($this->owner, 'sanctum')->getJson('/api/partner/payment-details')->assertStatus(200);
        $this->assertNotEmpty($details->json('qr_url'));
        $details->assertJsonPath('upi_id', 'bookalook@upi')->assertJsonPath('payee_name', 'BookALook');

        $this->actingAs($this->superadmin, 'sanctum')->deleteJson('/api/superadmin/settings/payment-qr')->assertStatus(200);
        $this->actingAs($this->owner, 'sanctum')->getJson('/api/partner/payment-details')->assertJsonPath('qr_url', null);
    }

    public function test_only_superadmin_sets_the_qr(): void
    {
        $this->actingAs($this->owner, 'sanctum')
            ->post('/api/superadmin/settings/payment-qr', ['qr' => $this->png()], ['Accept' => 'application/json'])
            ->assertStatus(403);
    }
}
