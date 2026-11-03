<?php

namespace Tests\Support;

use App\Models\Appointment;
use App\Models\User;
use App\Services\Payments\PaymentGateway;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;

/**
 * For tests of the online payment path: switch a gateway on, and pay through
 * it the way the app would after the provider's checkout succeeds.
 */
trait PaysOnline
{
    protected FakePaymentGateway $fakeGateway;

    protected function useFakePaymentGateway(): void
    {
        $this->fakeGateway = new FakePaymentGateway();
        $this->app->instance(PaymentGateway::class, $this->fakeGateway);
    }

    /**
     * The payment id and signature the provider would return for this
     * booking's open order. Null when no order was opened.
     *
     * @return array{payment_id: string, signature: string}|null
     */
    protected function simulateOnlinePayment(Appointment $appointment): ?array
    {
        $order = DB::table('payment_orders')
            ->where('appointment_id', $appointment->id)
            ->whereIn('status', ['created', 'paid', 'abandoned'])
            ->orderByDesc('created_at')
            ->first();

        if (! $order) {
            return null;
        }

        $paymentId = 'pay_fake_' . Str::lower(Str::random(14));

        return [
            'payment_id' => $paymentId,
            'signature' => ($this->fakeGateway ?? new FakePaymentGateway())->sign($order->gateway_order_id, $paymentId),
        ];
    }

    /** Pay for a booking online, as the customer, through the confirm endpoint. */
    protected function payOnline(User $customer, string $appointmentId): TestResponse
    {
        $simulated = $this->simulateOnlinePayment(Appointment::findOrFail($appointmentId));

        return $this->actingAs($customer, 'sanctum')->postJson(
            "/api/customer/appointments/{$appointmentId}/payment/confirm",
            $simulated ?? ['payment_id' => 'missing', 'signature' => 'missing']
        );
    }
}
