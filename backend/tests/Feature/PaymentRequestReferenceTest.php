<?php

namespace Tests\Feature;

use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPaymentRequest;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Support\BillingModel;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * The transaction id and note a salon owner types alongside their payment
 * screenshot.
 *
 * What is being defended:
 *
 *  1. Both are genuinely optional. Plenty of owners pay by card or over the
 *     counter and have no UTR to quote, so a request without either must still
 *     be accepted — and must still be reviewable by SuperAdmin.
 *  2. They reach both sides. A field SuperAdmin cannot see is not a field, and a
 *     field the owner cannot find afterwards is worse than not having offered
 *     it at all.
 *  3. A blank is stored as null, so "nothing typed" and "left empty" are one
 *     value and the screens never have to tell them apart.
 *
 * Runs inside a transaction so it can use the development database without
 * leaving anything behind.
 */
class PaymentRequestReferenceTest extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();

        // The real disk is Cloudinary, which is not reachable from a test.
        Storage::fake('cloudinary');
    }

    /**
     * A receipt screenshot that passes the controller's `image` rule.
     *
     * UploadedFile::fake()->image() draws a real image, which needs the GD
     * extension — not something every machine running this suite has, and not
     * something this test cares about. A real 70-byte PNG header is enough:
     * what is under test is that the reference beside it is stored and read
     * back, not what the picture looks like.
     */
    private function receipt(): UploadedFile
    {
        return UploadedFile::fake()->createWithContent(
            'receipt.png',
            base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')
        );
    }

    public function test_the_owner_can_supply_a_transaction_id_and_a_note(): void
    {
        [$salon, $plan] = $this->fixture();

        $this->actingAs(User::findOrFail($salon->admin_id), 'sanctum')
            ->post("/api/partner/salons/{$salon->id}/subscription/payment-request", [
                'plan_id' => $plan->id,
                'transaction_id' => '  UTR-99887766  ',
                'note' => 'Paid from my business account, UPI to the BookALook QR.',
                'screenshot' => $this->receipt(),
            ])
            ->assertStatus(200);

        $request = SubscriptionPaymentRequest::where('salon_id', $salon->id)
            ->where('status', 'pending')
            ->firstOrFail();

        // Trimmed on the way in, so a stray space cannot stop a search for a
        // copied reference from matching.
        $this->assertSame('UTR-99887766', $request->transaction_id);
        $this->assertSame(
            'Paid from my business account, UPI to the BookALook QR.',
            $request->note
        );
    }

    public function test_both_are_optional(): void
    {
        [$salon, $plan] = $this->fixture();

        $this->actingAs(User::findOrFail($salon->admin_id), 'sanctum')
            ->post("/api/partner/salons/{$salon->id}/subscription/payment-request", [
                'plan_id' => $plan->id,
                'screenshot' => $this->receipt(),
            ])
            ->assertStatus(200);

        $request = SubscriptionPaymentRequest::where('salon_id', $salon->id)
            ->where('status', 'pending')
            ->firstOrFail();

        $this->assertNotNull($request->screenshot_url);
        $this->assertNull($request->transaction_id);
        $this->assertNull($request->note);
    }

    public function test_an_untouched_field_is_stored_as_null_not_as_an_empty_string(): void
    {
        [$salon, $plan] = $this->fixture();

        // A text input that was shown but never typed into sends "".
        $this->actingAs(User::findOrFail($salon->admin_id), 'sanctum')
            ->post("/api/partner/salons/{$salon->id}/subscription/payment-request", [
                'plan_id' => $plan->id,
                'transaction_id' => '',
                'note' => '   ',
                'screenshot' => $this->receipt(),
            ])
            ->assertStatus(200);

        $request = SubscriptionPaymentRequest::where('salon_id', $salon->id)
            ->where('status', 'pending')
            ->firstOrFail();

        $this->assertNull($request->transaction_id);
        $this->assertNull($request->note);
    }

    public function test_superadmin_sees_them_on_the_pending_queue(): void
    {
        [$salon, $plan] = $this->fixture();

        $this->actingAs(User::findOrFail($salon->admin_id), 'sanctum')
            ->post("/api/partner/salons/{$salon->id}/subscription/payment-request", [
                'plan_id' => $plan->id,
                'transaction_id' => 'UTR-11223344',
                'note' => 'Transferred from the joint account.',
                'screenshot' => $this->receipt(),
            ])
            ->assertStatus(200);

        $row = collect($this->actingAs($this->superAdmin(), 'sanctum')
            ->getJson('/api/superadmin/subscription-requests')
            ->assertStatus(200)
            ->json('requests'))
            ->firstWhere('salon_id', $salon->id);

        $this->assertNotNull($row);
        $this->assertSame('UTR-11223344', $row['transaction_id']);
        $this->assertSame('Transferred from the joint account.', $row['note']);
    }

    public function test_the_queue_defaults_to_pending_and_can_be_widened_to_everything(): void
    {
        [$salon, $plan] = $this->fixture();
        $owner = User::findOrFail($salon->admin_id);

        $this->actingAs($owner, 'sanctum')
            ->post("/api/partner/salons/{$salon->id}/subscription/payment-request", [
                'plan_id' => $plan->id,
                'transaction_id' => 'UTR-55556666',
                'screenshot' => $this->receipt(),
            ])
            ->assertStatus(200);

        $pending = SubscriptionPaymentRequest::where('salon_id', $salon->id)->firstOrFail();

        // The dashboard is built around the queue, so the default must not move.
        SubscriptionPaymentRequest::where('id', $pending->id)->update(['status' => 'rejected']);

        $this->assertCount(
            0,
            $this->actingAs($this->superAdmin(), 'sanctum')
                ->getJson('/api/superadmin/subscription-requests')
                ->json('requests')
        );

        $all = collect($this->actingAs($this->superAdmin(), 'sanctum')
            ->getJson('/api/superadmin/subscription-requests?status=all')
            ->assertStatus(200)
            ->json('requests'))
            ->firstWhere('id', $pending->id);

        $this->assertNotNull($all, 'a decided request must stay auditable');
        $this->assertSame('rejected', $all['status']);
        // The reference the owner gave is why the row is worth keeping at all.
        $this->assertSame('UTR-55556666', $all['transaction_id']);
    }

    public function test_the_owner_can_read_their_own_payment_history(): void
    {
        [$salon, $plan] = $this->fixture();
        $owner = User::findOrFail($salon->admin_id);

        $this->actingAs($owner, 'sanctum')
            ->post("/api/partner/salons/{$salon->id}/subscription/payment-request", [
                'plan_id' => $plan->id,
                'transaction_id' => 'UTR-77889900',
                'note' => 'Settled in full.',
                'screenshot' => $this->receipt(),
            ])
            ->assertStatus(200);

        $request = SubscriptionPaymentRequest::where('salon_id', $salon->id)->firstOrFail();

        // SuperAdmin decides, and the request stops being pending.
        SubscriptionPaymentRequest::where('id', $request->id)->update(['status' => 'approved']);

        $row = collect($this->actingAs($owner, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/subscription")
            ->assertStatus(200)
            ->json('payment_requests'))
            ->firstWhere('id', $request->id);

        $this->assertNotNull($row, 'an owner who uploaded proof must be able to find it afterwards');
        $this->assertSame('approved', $row['status']);
        $this->assertSame('UTR-77889900', $row['transaction_id']);
        $this->assertSame('Settled in full.', $row['note']);
        $this->assertSame($plan->name, $row['plan_name']);
        $this->assertNotNull($row['screenshot_url']);
    }

    public function test_another_salons_history_is_not_visible(): void
    {
        [$salon, $plan] = $this->fixture();
        [$other] = $this->fixture();

        $this->actingAs(User::findOrFail($salon->admin_id), 'sanctum')
            ->post("/api/partner/salons/{$salon->id}/subscription/payment-request", [
                'plan_id' => $plan->id,
                'transaction_id' => 'UTR-31313131',
                'screenshot' => $this->receipt(),
            ])
            ->assertStatus(200);

        $history = $this->actingAs(User::findOrFail($other->admin_id), 'sanctum')
            ->getJson("/api/partner/salons/{$other->id}/subscription")
            ->assertStatus(200)
            ->json('payment_requests');

        $this->assertCount(0, $history);
    }

    // ------------------------------------------------------------- fixtures

    private function superAdmin(): User
    {
        $user = User::where('role', 'superadmin')->first() ?? User::where('role', 'admin')->first();

        if (! $user) {
            $this->markTestSkipped('needs an elevated account');
        }

        return $user;
    }

    /** @return array{0: Salon, 1: SubscriptionPlan} */
    private function fixture(): array
    {
        $unique = substr(bin2hex(random_bytes(6)), 0, 10);

        $admin = User::create([
            'name' => "Reference Admin {$unique}",
            'phone' => '9' . substr((string) crc32($unique), 0, 9),
            'password_hash' => 'x',
            'role' => 'admin',
            'is_active' => true,
        ]);

        $salon = Salon::create([
            'admin_id' => $admin->id,
            'name' => "Reference Salon {$unique}",
            'slug' => "reference-salon-{$unique}",
            'address' => 'Test address',
            // Location is a relation now, not a free-text column, and the city
            // itself is irrelevant to a payment reference.
            'city_id' => null,
            'submitted_by' => $admin->id,
            'status' => 'active',
        ]);

        $plan = SubscriptionPlan::purchasable()->first() ?? SubscriptionPlan::first();

        if (! $plan) {
            $this->markTestSkipped('needs a subscription plan');
        }

        // Renewal sits behind the salon.active gate in the app, and the billing
        // screen reads the current plan — so the salon needs one to be on.
        SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'billing_type' => BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => $plan->price,
            'start_date' => Carbon::today()->subDay(),
            'end_date' => Carbon::today()->addDays(30),
            'status' => 'active',
        ]);

        return [$salon, $plan];
    }
}
