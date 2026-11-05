<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\ProviderWorkingHour;
use App\Models\Salon;
use App\Models\SalonWorkingHour;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceProvider;
use App\Models\ServiceTemplate;
use App\Models\User;
use App\Services\Payments\PaymentGateway;
use App\Services\Payments\RazorpayGateway;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\Support\PaysOnline;
use Tests\TestCase;

/**
 * SuperAdmin's partial-advance and full-payment switches, the customer's
 * optional "pay full" choice, how a full payment is refunded, and Razorpay.
 */
class PaymentOptionsTest extends TestCase
{
    use DatabaseTransactions;
    use PaysOnline;
    use \Tests\Feature\Concerns\ActivatesSalons;

    private User $owner;
    private User $customer;
    private Salon $salon;
    private Service $refundable;   // 20% advance, refunded on cancel
    private Service $keepsAdvance; // 40% advance, kept on cancel
    private Service $noAdvanceSet; // advance never set
    private ServiceProvider $provider;

    protected function setUp(): void
    {
        parent::setUp();

        $this->owner = $this->user('admin');
        $this->customer = $this->user('customer');
        $this->salon = $this->activateSalon(Salon::create([
            'id' => (string) Str::uuid(), 'admin_id' => $this->owner->id, 'name' => 'Options Salon',
            'slug' => 'options-' . Str::random(5), 'address' => 'x', 'submitted_by' => $this->owner->id, 'status' => 'active',
        ]));

        $category = ServiceCategory::firstOrCreate(['name' => 'Hair Care'], ['id' => (string) Str::uuid(), 'is_active' => true]);
        $make = function (float $price, ?float $pct, bool $refund) use ($category) {
            $template = ServiceTemplate::create([
                'id' => (string) Str::uuid(), 'name' => 'Svc ' . Str::random(6), 'category_id' => $category->id,
                'estimated_duration_minutes' => 30, 'is_active' => true,
            ]);

            return Service::create([
                'id' => (string) Str::uuid(), 'salon_id' => $this->salon->id, 'template_id' => $template->id,
                'price' => $price, 'duration_minutes' => 30, 'advance_percentage' => $pct,
                'will_refund_advance_if_cancelled' => $refund, 'is_active' => true,
            ]);
        };
        $this->refundable = $make(1000.0, 20.0, true);
        $this->keepsAdvance = $make(500.0, 40.0, false);
        $this->noAdvanceSet = $make(300.0, null, false);

        $this->provider = ServiceProvider::create([
            'id' => (string) Str::uuid(), 'user_id' => $this->user('service_provider')->id,
            'salon_id' => $this->salon->id, 'is_active' => true,
        ]);
        $this->provider->services()->attach([$this->refundable->id, $this->keepsAdvance->id, $this->noAdvanceSet->id]);

        for ($d = 0; $d <= 6; $d++) {
            SalonWorkingHour::create(['salon_id' => $this->salon->id, 'day_of_week' => $d, 'open_time' => '09:00:00', 'close_time' => '19:00:00', 'is_closed' => false]);
            ProviderWorkingHour::create(['provider_id' => $this->provider->id, 'day_of_week' => $d, 'shift_start' => '09:00:00', 'shift_end' => '19:00:00', 'is_weekly_off' => false]);
        }
    }

    private function user(string $role): User
    {
        $u = Str::random(8);

        return User::create([
            'id' => (string) Str::uuid(), 'name' => "User {$u}", 'phone' => '7' . substr((string) crc32($u), 0, 9),
            'password_hash' => bcrypt('password'), 'role' => $role, 'is_active' => true,
        ]);
    }

    /** @param Service[] $services */
    private function fillCart(array $services): void
    {
        Cart::where('customer_id', $this->customer->id)->where('status', 'active')->delete();
        $cart = Cart::create(['id' => (string) Str::uuid(), 'customer_id' => $this->customer->id, 'salon_id' => $this->salon->id, 'status' => 'active']);
        foreach ($services as $service) {
            CartItem::create(['id' => (string) Str::uuid(), 'cart_id' => $cart->id, 'service_id' => $service->id, 'quantity' => 1]);
        }
    }

    private function quote(): array
    {
        return $this->actingAs($this->customer, 'sanctum')
            ->getJson("/api/customer/salons/{$this->salon->id}/availability?" . http_build_query([
                'date' => Carbon::tomorrow()->toDateString(),
                'provider_id' => $this->provider->id,
            ]))
            ->assertOk()
            ->json();
    }

    private function book(array $extra = [], string $time = '10:00')
    {
        return $this->actingAs($this->customer, 'sanctum')->postJson(
            "/api/customer/salons/{$this->salon->id}/appointments/book",
            ['date' => Carbon::tomorrow()->toDateString(), 'time' => $time, 'provider_id' => $this->provider->id] + $extra
        )->assertStatus(201);
    }

    public function test_with_partial_advance_off_nothing_is_asked_at_booking(): void
    {
        $this->useFakePaymentGateway();
        $this->setPaymentOption('partial_advance_enabled', false);
        $this->fillCart([$this->refundable, $this->keepsAdvance]);

        $quote = $this->quote();
        $this->assertEquals(0, $quote['advance_amount']);
        $this->assertFalse($quote['partial_advance_enabled']);
        $this->assertFalse($quote['full_payment_available'], 'full payment is off too');

        $res = $this->book();
        $res->assertJsonPath('payment_required', false);
        $appointment = Appointment::findOrFail($res->json('appointment.id'));
        $this->assertSame('scheduled', $appointment->status);
        $this->assertEquals(0, (float) $appointment->advance_due);

        // The salon's saved percentages are untouched.
        $this->assertEquals(20.0, (float) $this->refundable->fresh()->advance_percentage);
        $this->assertEquals(40.0, (float) $this->keepsAdvance->fresh()->advance_percentage);
    }

    public function test_with_partial_advance_on_each_service_asks_its_own_minimum_and_unset_is_zero(): void
    {
        $this->useFakePaymentGateway();
        $this->setPaymentOption('partial_advance_enabled', true);
        $this->fillCart([$this->refundable, $this->keepsAdvance, $this->noAdvanceSet]);

        // 20% of 1000 + 40% of 500 + 0% of 300.
        $quote = $this->quote();
        $this->assertEquals(400, $quote['advance_amount']);
        $this->assertEquals(400, $quote['minimum_advance']);

        $res = $this->book();
        $res->assertJsonPath('payment_required', true);
        $res->assertJsonPath('payment.amount', 400);
        $appointment = Appointment::findOrFail($res->json('appointment.id'));
        $this->assertSame('advance_only', $appointment->payment_option);
        $this->assertEquals(400, (float) $appointment->minimum_advance);
    }

    public function test_turning_partial_advance_off_and_on_brings_the_same_percentages_back(): void
    {
        $this->setPaymentOption('partial_advance_enabled', false);

        // While off, the owner cannot change (or wipe) the saved minimum.
        $this->actingAs($this->owner, 'sanctum')
            ->putJson("/api/partner/salons/{$this->salon->id}/services/{$this->refundable->id}", ['advance_percentage' => 0, 'price' => 1000])
            ->assertOk();
        $this->assertEquals(20.0, (float) $this->refundable->fresh()->advance_percentage);

        $list = $this->actingAs($this->owner, 'sanctum')->getJson("/api/partner/salons/{$this->salon->id}/services")->assertOk();
        $this->assertFalse($list->json('partial_advance_enabled'));

        $this->setPaymentOption('partial_advance_enabled', true);
        $this->fillCart([$this->refundable]);
        $this->assertEquals(200, $this->quote()['advance_amount']);

        // While on, the owner sets it per service.
        $this->actingAs($this->owner, 'sanctum')
            ->putJson("/api/partner/salons/{$this->salon->id}/services/{$this->refundable->id}", ['advance_percentage' => 50])
            ->assertOk();
        $this->assertEquals(500, $this->quote()['advance_amount']);
    }

    public function test_pay_full_is_only_offered_while_superadmin_has_it_on(): void
    {
        $this->useFakePaymentGateway();
        $this->setPaymentOption('partial_advance_enabled', true);
        $this->setPaymentOption('full_payment_enabled', false);
        $this->fillCart([$this->refundable]);

        $this->assertFalse($this->quote()['full_payment_available']);

        // Asking anyway is ignored: the advance is charged.
        $res = $this->book(['pay_full' => true]);
        $res->assertJsonPath('payment.amount', 200);
        $this->assertSame('advance_only', Appointment::findOrFail($res->json('appointment.id'))->payment_option);
    }

    public function test_pay_full_is_never_offered_without_a_gateway(): void
    {
        $this->setPaymentOption('full_payment_enabled', true);
        $this->fillCart([$this->refundable]);

        $this->assertFalse($this->quote()['full_payment_available']);
    }

    public function test_the_customer_may_choose_to_pay_the_full_amount(): void
    {
        $this->useFakePaymentGateway();
        $this->setPaymentOption('partial_advance_enabled', true);
        $this->setPaymentOption('full_payment_enabled', true);
        $this->fillCart([$this->refundable, $this->keepsAdvance]);

        $quote = $this->quote();
        $this->assertTrue($quote['full_payment_available']);
        $this->assertEquals(1500, $quote['total_amount']);

        $res = $this->book(['pay_full' => true]);
        $res->assertJsonPath('payment.amount', 1500);
        $appointment = Appointment::findOrFail($res->json('appointment.id'));
        $this->assertSame('full_optional', $appointment->payment_option);
        $this->assertEquals(400, (float) $appointment->minimum_advance);

        $this->payOnline($this->customer, $appointment->id)->assertOk();
        $appointment->refresh();
        $this->assertSame('scheduled', $appointment->status);
        $this->assertEquals(1500, (float) $appointment->advance_amount);
        $this->assertEquals(0, (float) $appointment->balance_amount);
        $this->assertDatabaseHas('payments', ['appointment_id' => $appointment->id, 'payment_type' => 'full', 'gateway' => 'fake']);
    }

    public function test_full_payment_with_partial_advance_off_still_works(): void
    {
        $this->useFakePaymentGateway();
        $this->setPaymentOption('partial_advance_enabled', false);
        $this->setPaymentOption('full_payment_enabled', true);
        $this->fillCart([$this->refundable]);

        $this->assertTrue($this->quote()['full_payment_available']);

        // Not choosing it: booked with nothing to pay.
        $this->book()->assertJsonPath('payment_required', false);

        // Choosing it: the full 1000. (The confirmed booking emptied the cart.)
        $this->fillCart([$this->refundable]);
        $this->book(['pay_full' => true], '12:00')->assertJsonPath('payment.amount', 1000);
    }

    public function test_cancelling_a_full_payment_returns_everything_above_the_advance_and_the_advance_follows_each_service(): void
    {
        $this->useFakePaymentGateway();
        $this->setPaymentOption('partial_advance_enabled', true);
        $this->setPaymentOption('full_payment_enabled', true);
        $this->fillCart([$this->refundable, $this->keepsAdvance]);

        $appointment = Appointment::findOrFail($this->book(['pay_full' => true])->json('appointment.id'));
        $this->payOnline($this->customer, $appointment->id)->assertOk();

        $res = $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointment->id}/cancel", ['reason' => 'Plans changed'])
            ->assertOk();

        // Paid 1500, minimum advance 400. The 1100 above it always comes back.
        // The 400 is split by price (1000:500): 266.67 on the refundable
        // service comes back, 133.33 on the other is kept.
        $this->assertEquals(1366.67, $res->json('refund.refundable'));
        $this->assertEquals(133.33, $res->json('refund.forfeited'));
        $this->assertEquals(1366.67, (float) DB::table('payment_refunds')->where('appointment_id', $appointment->id)->sum('amount'));
    }

    public function test_razorpay_signatures_and_webhooks_are_verified(): void
    {
        $gateway = new RazorpayGateway('rzp_test_key', 'secret_value', 'BookALook', 'hook_secret');

        $this->assertTrue($gateway->isEnabled());
        $this->assertFalse((new RazorpayGateway('', '', 'BookALook'))->isEnabled());

        $good = hash_hmac('sha256', 'order_1|pay_1', 'secret_value');
        $this->assertTrue($gateway->verifySignature('order_1', 'pay_1', $good));
        $this->assertFalse($gateway->verifySignature('order_1', 'pay_2', $good));

        $body = '{"event":"payment.captured"}';
        $this->assertTrue($gateway->verifyWebhook($body, hash_hmac('sha256', $body, 'hook_secret')));
        $this->assertFalse($gateway->verifyWebhook($body, 'nope'));
        $this->assertFalse((new RazorpayGateway('k', 's', 'B', ''))->verifyWebhook($body, hash_hmac('sha256', $body, '')));
    }

    public function test_the_webhook_confirms_a_paid_booking_the_app_never_confirmed(): void
    {
        $this->setPaymentOption('partial_advance_enabled', true);
        $gateway = new class('rzp_test_key', 'secret_value', 'BookALook', 'hook_secret') extends RazorpayGateway {
            public function createOrder(float $amountInRupees, string $receipt, array $notes = []): \App\Services\Payments\GatewayOrder
            {
                return new \App\Services\Payments\GatewayOrder('order_' . Str::random(10), (int) round($amountInRupees * 100), 'INR', 'razorpay');
            }
        };
        $this->app->instance(PaymentGateway::class, $gateway);
        $this->fillCart([$this->refundable]);

        $appointment = Appointment::findOrFail($this->book()->json('appointment.id'));
        $this->assertSame('pending_payment', $appointment->status);
        $orderId = DB::table('payment_orders')->where('appointment_id', $appointment->id)->value('gateway_order_id');

        $body = json_encode([
            'event' => 'payment.captured',
            'payload' => ['payment' => ['entity' => ['id' => 'pay_hook_1', 'order_id' => $orderId, 'amount' => 20000]]],
        ]);

        // A forged call changes nothing.
        $this->call('POST', '/api/payments/razorpay/webhook', [], [], [], [
            'CONTENT_TYPE' => 'application/json', 'HTTP_X_RAZORPAY_SIGNATURE' => 'forged',
        ], $body)->assertStatus(401);
        $this->assertSame('pending_payment', $appointment->fresh()->status);

        $send = fn () => $this->call('POST', '/api/payments/razorpay/webhook', [], [], [], [
            'CONTENT_TYPE' => 'application/json',
            'HTTP_X_RAZORPAY_SIGNATURE' => hash_hmac('sha256', $body, 'hook_secret'),
        ], $body)->assertOk();

        $send();
        $send(); // Razorpay retries; nothing is recorded twice.

        $this->assertSame('scheduled', $appointment->fresh()->status);
        $this->assertSame(1, DB::table('payments')->where('appointment_id', $appointment->id)->count());
        $this->assertDatabaseHas('payments', ['appointment_id' => $appointment->id, 'gateway_transaction_id' => 'pay_hook_1', 'amount' => 200]);
    }
}
