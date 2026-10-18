<?php

namespace Tests\Feature;

use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\SalonWallet;
use App\Models\SubscriptionPaymentRequest;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Models\WalletScheme;
use App\Services\SalonAccessService;
use App\Support\BillingModel;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class SubscriptionPaymentVerificationTest extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('cloudinary');
    }

    private function receipt(): UploadedFile
    {
        return UploadedFile::fake()->createWithContent(
            'receipt.png',
            base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')
        );
    }

    private function getOrCreatePlan(string $name = 'Growth Test Plan', float $price = 1999.00, int $days = 30): SubscriptionPlan
    {
        return SubscriptionPlan::firstOrCreate(
            ['name' => $name],
            [
                'price' => $price,
                'validity_days' => $days,
                'whatsapp_campaign_limit' => 5,
                'is_active' => true,
                'is_commission_plan' => false,
            ]
        );
    }

    private function fixture(bool $withActiveSubscription = false): array
    {
        $unique = substr(bin2hex(random_bytes(6)), 0, 10);

        $admin = User::create([
            'name' => "Admin {$unique}",
            'phone' => '9' . substr((string) crc32($unique), 0, 9),
            'password_hash' => 'x',
            'role' => 'admin',
            'is_active' => true,
        ]);

        $salon = Salon::create([
            'admin_id' => $admin->id,
            'name' => "Salon {$unique}",
            'slug' => "salon-{$unique}",
            'address' => 'Test address',
            'city_id' => null,
            'submitted_by' => $admin->id,
            'status' => 'active',
        ]);

        $plan = $this->getOrCreatePlan();

        if ($withActiveSubscription) {
            SalonSubscription::create([
                'salon_id' => $salon->id,
                'plan_id' => $plan->id,
                'billing_type' => BillingModel::SUBSCRIPTION,
                'plan_price_snapshot' => $plan->price,
                'start_date' => Carbon::today()->subDays(5),
                'end_date' => Carbon::today()->addDays(25),
                'status' => 'active',
            ]);
        }

        return [$salon, $plan, $admin];
    }

    public function test_pending_payment_request_appears_in_subscription_response(): void
    {
        [$salon, $plan, $admin] = $this->fixture(withActiveSubscription: false);

        // Upload payment proof
        $res = $this->actingAs($admin, 'sanctum')
            ->post("/api/partner/salons/{$salon->id}/subscription/payment-request", [
                'plan_id' => $plan->id,
                'transaction_id' => 'UTR123456789',
                'note' => 'Payment from HDFC bank account',
                'screenshot' => $this->receipt(),
            ])
            ->assertStatus(200)
            ->json();

        $this->assertTrue($res['success']);
        $this->assertNotNull($res['data']);
        $this->assertSame('UTR123456789', $res['data']['transaction_id']);

        // Check getSubscription response
        $subRes = $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/subscription")
            ->assertStatus(200)
            ->json();

        $this->assertTrue($subRes['success']);
        $pending = $subRes['pending_request'];
        $this->assertNotNull($pending, 'pending_request should be present');
        $this->assertSame('pending', $pending['status']);
        $this->assertSame($plan->name, $pending['plan_name']);
        $this->assertSame((float) $plan->price, (float) $pending['base_price']);
        $this->assertSame((float) $plan->price, (float) $pending['amount_payable_inr']);
        $this->assertSame('UTR123456789', $pending['transaction_id']);
        $this->assertNotNull($pending['screenshot_url']);
        $this->assertNotNull($pending['raised_at']);
    }

    public function test_locked_screen_payload_includes_pending_request_details(): void
    {
        [$salon, $plan, $admin] = $this->fixture(withActiveSubscription: false);

        // Create pending request
        $this->actingAs($admin, 'sanctum')
            ->post("/api/partner/salons/{$salon->id}/subscription/payment-request", [
                'plan_id' => $plan->id,
                'transaction_id' => 'UTR999',
                'screenshot' => $this->receipt(),
            ])
            ->assertStatus(200);

        $service = app(SalonAccessService::class);
        $payload = $service->partnerPayload($salon);

        $this->assertTrue($payload['is_locked'], 'Salon must remain locked while pending approval');
        $this->assertTrue($payload['has_pending_request']);
        $this->assertNotNull($payload['pending_request']);
        $this->assertSame('pending', $payload['pending_request']['status']);
        $this->assertSame('UTR999', $payload['pending_request']['transaction_id']);
    }

    public function test_pending_status_does_not_activate_entitlements(): void
    {
        [$salon, $plan, $admin] = $this->fixture(withActiveSubscription: false);

        $service = app(SalonAccessService::class);
        $this->assertFalse($service->isActive($salon->id), 'Salon without plan is inactive');

        // Submit payment proof
        $this->actingAs($admin, 'sanctum')
            ->post("/api/partner/salons/{$salon->id}/subscription/payment-request", [
                'plan_id' => $plan->id,
                'screenshot' => $this->receipt(),
            ])
            ->assertStatus(200);

        // Salon must STILL be inactive
        $this->assertFalse($service->isActive($salon->id), 'Salon must not be active while approval is pending');
    }

    public function test_an_owner_cannot_access_another_salons_subscription(): void
    {
        [$salon1, $plan1, $admin1] = $this->fixture();
        [$salon2, $plan2, $admin2] = $this->fixture();

        // Admin 1 attempts to access Salon 2's subscription
        $this->actingAs($admin1, 'sanctum')
            ->getJson("/api/partner/salons/{$salon2->id}/subscription")
            ->assertStatus(404);
    }

    public function test_replacing_a_pending_request_marks_previous_as_rejected(): void
    {
        [$salon, $plan, $admin] = $this->fixture(withActiveSubscription: false);

        // First submission
        $this->actingAs($admin, 'sanctum')
            ->post("/api/partner/salons/{$salon->id}/subscription/payment-request", [
                'plan_id' => $plan->id,
                'transaction_id' => 'FIRST-UTR',
                'screenshot' => $this->receipt(),
            ])
            ->assertStatus(200);

        $first = SubscriptionPaymentRequest::where('salon_id', $salon->id)
            ->where('transaction_id', 'FIRST-UTR')
            ->firstOrFail();
        $this->assertSame('pending', $first->status);

        // Second submission (replaces first)
        $this->actingAs($admin, 'sanctum')
            ->post("/api/partner/salons/{$salon->id}/subscription/payment-request", [
                'plan_id' => $plan->id,
                'transaction_id' => 'SECOND-UTR',
                'screenshot' => $this->receipt(),
            ])
            ->assertStatus(200);

        $this->assertSame('rejected', $first->fresh()->status, 'Previous pending request must be rejected');

        $second = SubscriptionPaymentRequest::where('salon_id', $salon->id)
            ->where('transaction_id', 'SECOND-UTR')
            ->firstOrFail();
        $this->assertSame('pending', $second->status);
    }

    public function test_existing_active_subscription_remains_active_while_upgrade_is_pending(): void
    {
        [$salon, $plan, $admin] = $this->fixture(withActiveSubscription: true);

        $service = app(SalonAccessService::class);
        $this->assertTrue($service->isActive($salon->id), 'Salon is active from initial plan');

        $upgradePlan = $this->getOrCreatePlan('Premium Upgrade Plan', 3999.00, 60);

        // Owner submits an upgrade request
        $this->actingAs($admin, 'sanctum')
            ->post("/api/partner/salons/{$salon->id}/subscription/payment-request", [
                'plan_id' => $upgradePlan->id,
                'transaction_id' => 'UPGRADE-UTR',
                'screenshot' => $this->receipt(),
            ])
            ->assertStatus(200);

        // Check subscription API response
        $subRes = $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/subscription")
            ->assertStatus(200)
            ->json();

        $this->assertTrue($subRes['has_subscription'], 'Active subscription must still be shown');
        $this->assertSame($plan->id, $subRes['subscription']['plan_id'], 'Current plan must still be the active one');
        $this->assertNotNull($subRes['pending_request'], 'Pending upgrade request must be returned separately');
        $this->assertSame('Premium Upgrade Plan', $subRes['pending_request']['plan_name']);
        $this->assertTrue($service->isActive($salon->id), 'Salon must stay active under current plan');
    }

    public function test_superadmin_approval_activates_subscription_and_marks_request_approved(): void
    {
        [$salon, $plan, $admin] = $this->fixture(withActiveSubscription: false);

        $this->actingAs($admin, 'sanctum')
            ->post("/api/partner/salons/{$salon->id}/subscription/payment-request", [
                'plan_id' => $plan->id,
                'transaction_id' => 'APPROVE-ME',
                'screenshot' => $this->receipt(),
            ])
            ->assertStatus(200);

        $paymentReq = SubscriptionPaymentRequest::where('salon_id', $salon->id)->firstOrFail();
        $this->assertSame('pending', $paymentReq->status);

        $superAdmin = User::create([
            'name' => 'Super Admin Test',
            'phone' => '8' . substr((string) crc32(bin2hex(random_bytes(4))), 0, 9),
            'password_hash' => 'x',
            'role' => 'superadmin',
            'is_active' => true,
        ]);

        // SuperAdmin assigns and approves the subscription
        $this->actingAs($superAdmin, 'sanctum')
            ->postJson("/api/superadmin/salons/{$salon->id}/subscription", [
                'billing_type' => BillingModel::SUBSCRIPTION,
                'plan_id' => $plan->id,
            ])
            ->assertStatus(200);

        $this->assertSame('approved', $paymentReq->fresh()->status);

        $activeSub = SalonSubscription::where('salon_id', $salon->id)
            ->where('status', 'active')
            ->first();
        $this->assertNotNull($activeSub);
        $this->assertSame($plan->id, $activeSub->plan_id);

        $service = app(SalonAccessService::class);
        $this->assertTrue($service->isActive($salon->id), 'Salon entitlements must be active after approval');
    }
}
