<?php

namespace App\Services;

use App\Models\Appointment;
use App\Services\Payments\GatewayOrder;
use App\Services\Payments\PaymentGateway;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * The money half of booking an appointment.
 *
 * A booking is created as `pending_payment` first, which holds the slot while
 * the customer is on the payment sheet — otherwise two people could pay for the
 * same time. The hold expires, so an abandoned checkout gives the slot back
 * instead of keeping it forever.
 *
 * Only the appointment advance comes through here. Salon subscriptions are paid
 * by bank transfer and verified from a screenshot.
 */
class BookingPaymentService
{
    public function __construct(private PaymentGateway $gateway)
    {
    }

    public function holdMinutes(): int
    {
        return (int) config('services.razorpay.hold_minutes', 10);
    }

    /**
     * Open an order against a held appointment, reusing the one already open
     * if the customer is simply retrying — reopening the same sheet should not
     * leave a trail of orphan orders at the gateway.
     *
     * @return array{order: GatewayOrder, payment_order_id: string}
     */
    public function openOrder(Appointment $appointment, float $amount): array
    {
        $existing = DB::table('payment_orders')
            ->where('appointment_id', $appointment->id)
            ->where('status', 'created')
            ->where('amount', $amount)
            ->where('expires_at', '>', now())
            ->orderByDesc('created_at')
            ->first();

        if ($existing) {
            return [
                'order' => new GatewayOrder(
                    $existing->gateway_order_id,
                    (int) round((float) $existing->amount * 100),
                    $existing->currency,
                    $existing->gateway,
                ),
                'payment_order_id' => $existing->id,
            ];
        }

        $order = $this->gateway->createOrder(
            $amount,
            // Short enough for Razorpay's 40-character receipt limit.
            'apt_' . substr(str_replace('-', '', $appointment->id), 0, 32),
            [
                'appointment_id' => $appointment->id,
                'salon_id' => $appointment->salon_id,
            ]
        );

        $paymentOrderId = (string) Str::uuid();
        $attempt = DB::table('payment_orders')->where('appointment_id', $appointment->id)->count() + 1;

        DB::table('payment_orders')->insert([
            'id' => $paymentOrderId,
            'appointment_id' => $appointment->id,
            'amount' => $amount,
            'currency' => $order->currency,
            'gateway' => $order->gateway,
            'gateway_order_id' => $order->id,
            'status' => 'created',
            'expires_at' => now()->addMinutes($this->holdMinutes()),
            'idempotency_key' => "advance:{$appointment->id}:{$attempt}",
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return ['order' => $order, 'payment_order_id' => $paymentOrderId];
    }

    /**
     * What the app needs to open the checkout sheet.
     */
    public function checkoutPayload(Appointment $appointment, GatewayOrder $order, float $amount): array
    {
        return [
            'appointment_id' => $appointment->id,
            'gateway' => $order->gateway,
            'is_demo' => $this->gateway->isDemo(),
            'key' => $this->gateway->publicKey(),
            'name' => $this->gateway->displayName(),
            'order_id' => $order->id,
            'amount' => $amount,
            'amount_in_paise' => $order->amountInPaise,
            'currency' => $order->currency,
            'hold_expires_at' => $appointment->payment_hold_expires_at,
            'hold_minutes' => $this->holdMinutes(),
        ];
    }

    /**
     * Confirm a payment the app says succeeded.
     *
     * The signature is the whole security model: without it the client could
     * simply claim to have paid. Everything else here is bookkeeping.
     *
     * @return array{ok: bool, message: ?string}
     */
    public function confirm(
        Appointment $appointment,
        string $gatewayPaymentId,
        string $signature,
        string $actorId
    ): array {
        $order = DB::table('payment_orders')
            ->where('appointment_id', $appointment->id)
            ->orderByDesc('created_at')
            ->first();

        if (! $order) {
            return ['ok' => false, 'message' => 'No payment was started for this booking.'];
        }

        if ($order->status === 'paid') {
            // A retried callback must not charge or book twice.
            return ['ok' => true, 'message' => 'This payment was already confirmed.'];
        }

        if (! $this->gateway->verifySignature($order->gateway_order_id, $gatewayPaymentId, $signature)) {
            return ['ok' => false, 'message' => 'That payment could not be verified.'];
        }

        DB::transaction(function () use ($appointment, $order, $gatewayPaymentId, $signature, $actorId) {
            DB::table('payment_orders')
                ->where('id', $order->id)
                ->update(['status' => 'paid', 'updated_at' => now()]);

            DB::table('payments')->insert([
                'id' => (string) Str::uuid(),
                'appointment_id' => $appointment->id,
                'payment_order_id' => $order->id,
                'amount' => $order->amount,
                'currency' => $order->currency,
                'payment_type' => $this->paymentType($appointment, (float) $order->amount),
                'payment_mode' => 'online',
                'gateway' => $order->gateway,
                'gateway_transaction_id' => $gatewayPaymentId,
                'gateway_signature' => $signature,
                'status' => 'success',
                'paid_at' => now(),
                // Makes a duplicate callback a no-op at the database level too.
                'idempotency_key' => 'advance:' . $appointment->id,
                'metadata' => json_encode(['confirmed_by' => $actorId]),
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        });

        return ['ok' => true, 'message' => null];
    }

    /**
     * Stand in for the provider's "payment succeeded" callback while running on
     * the demo gateway.
     *
     * The signature is minted here rather than in the app because signing needs
     * the secret, and a secret shipped to a phone is not a secret. This is the
     * only reason the demo gateway exposes sign().
     *
     * @return array{payment_id: string, signature: string}|null
     */
    public function simulatePayment(Appointment $appointment): ?array
    {
        $gateway = $this->gateway;

        if (! $gateway instanceof \App\Services\Payments\DemoPaymentGateway) {
            return null;
        }

        $order = DB::table('payment_orders')
            ->where('appointment_id', $appointment->id)
            ->where('status', 'created')
            ->orderByDesc('created_at')
            ->first();

        if (! $order) {
            return null;
        }

        $paymentId = 'pay_demo_' . Str::lower(Str::random(14));

        return [
            'payment_id' => $paymentId,
            'signature' => $gateway->sign($order->gateway_order_id, $paymentId),
        ];
    }

    /**
     * Release a held slot the customer walked away from.
     */
    public function release(Appointment $appointment, string $reason): void
    {
        DB::transaction(function () use ($appointment, $reason) {
            DB::table('payment_orders')
                ->where('appointment_id', $appointment->id)
                ->where('status', 'created')
                ->update(['status' => 'abandoned', 'updated_at' => now()]);

            // Cancelled rather than deleted: an abandoned checkout is still
            // something the salon may want to see.
            $appointment->forceFill([
                'status' => 'cancelled',
                'cancelled_by' => 'system',
                'cancellation_reason' => $reason,
                'cancelled_at' => now(),
            ])->save();

            $appointment->services()->update(['line_status' => 'cancelled']);
        });
    }

    /**
     * Give back every slot whose payment hold has run out.
     */
    public function releaseExpiredHolds(): int
    {
        $stale = Appointment::where('status', 'pending_payment')
            ->whereNotNull('payment_hold_expires_at')
            ->where('payment_hold_expires_at', '<', now())
            ->get();

        foreach ($stale as $appointment) {
            $this->release($appointment, 'Payment was not completed in time.');
        }

        return $stale->count();
    }

    /**
     * Best-effort refund through the provider. A failure leaves the refund
     * pending rather than claiming money went back when it did not.
     */
    public function refund(string $gatewayPaymentId, float $amount, string $reason): ?string
    {
        try {
            return $this->gateway->refund($gatewayPaymentId, $amount, $reason);
        } catch (\Throwable $e) {
            report($e);

            return null;
        }
    }

    public function gateway(): PaymentGateway
    {
        return $this->gateway;
    }

    private function paymentType(Appointment $appointment, float $amount): string
    {
        return $amount >= (float) $appointment->total_amount ? 'full' : 'advance';
    }
}
