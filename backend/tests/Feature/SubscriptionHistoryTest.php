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
use Tests\TestCase;

class SubscriptionHistoryTest extends TestCase
{
    use DatabaseTransactions;

    public function test_superadmin_can_retrieve_salon_subscription_plans_history(): void
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

        $plan1 = SubscriptionPlan::firstOrCreate(
            ['name' => "Starter {$unique}"],
            [
                'price' => 1499.00,
                'validity_days' => 30,
                'whatsapp_campaign_limit' => 200,
                'is_active' => true,
                'is_commission_plan' => false,
            ]
        );

        $plan2 = SubscriptionPlan::firstOrCreate(
            ['name' => "Pro {$unique}"],
            [
                'price' => 2999.00,
                'validity_days' => 30,
                'whatsapp_campaign_limit' => 800,
                'is_active' => true,
                'is_commission_plan' => false,
            ]
        );

        // Previous expired subscription
        SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan1->id,
            'billing_type' => BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => $plan1->price,
            'start_date' => Carbon::today()->subDays(60),
            'end_date' => Carbon::today()->subDays(30),
            'status' => 'expired',
        ]);

        // Current active subscription
        $current = SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan2->id,
            'billing_type' => BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => $plan2->price,
            'start_date' => Carbon::today()->subDays(5),
            'end_date' => Carbon::today()->addDays(25),
            'status' => 'active',
        ]);

        // Payment request record
        SubscriptionPaymentRequest::create([
            'salon_id' => $salon->id,
            'subscription_plan_id' => $plan2->id,
            'billing_type' => BillingModel::SUBSCRIPTION,
            'transaction_id' => 'UTR987654321',
            'amount_payable_inr' => 2999.00,
            'status' => 'approved',
        ]);

        $superAdmin = User::create([
            'name' => "SuperAdmin {$unique}",
            'phone' => '8' . substr((string) crc32($unique . 'sa'), 0, 9),
            'password_hash' => 'x',
            'role' => 'superadmin',
            'is_active' => true,
        ]);

        $res = $this->actingAs($superAdmin, 'sanctum')
            ->getJson("/api/superadmin/salons/{$salon->id}/subscription-history")
            ->assertStatus(200)
            ->json();

        $this->assertTrue($res['success']);
        $this->assertSame($salon->name, $res['salon']['name']);
        $this->assertNotNull($res['current_subscription']);
        $this->assertSame("Pro {$unique}", $res['current_subscription']['plan_name']);
        $this->assertCount(2, $res['subscriptions']);
        $this->assertCount(1, $res['payment_requests']);
        $this->assertSame('UTR987654321', $res['payment_requests'][0]['transaction_id']);
    }
}
