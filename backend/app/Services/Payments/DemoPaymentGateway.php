<?php

namespace App\Services\Payments;

use Illuminate\Support\Str;

/**
 * Stands in for Razorpay until live keys exist.
 *
 * It signs and verifies with the same HMAC scheme the real gateway uses, so the
 * order → pay → verify → confirm path is genuinely exercised rather than
 * skipped. What it does not do is move money, which is why every response says
 * so and the app shows an unmistakable demo sheet.
 */
class DemoPaymentGateway implements PaymentGateway
{
    public function __construct(private string $secret, private string $displayName)
    {
    }

    public function createOrder(float $amountInRupees, string $receipt, array $notes = []): GatewayOrder
    {
        return new GatewayOrder(
            id: 'order_demo_' . Str::lower(Str::random(14)),
            amountInPaise: (int) round($amountInRupees * 100),
            currency: 'INR',
            gateway: 'demo',
            raw: ['receipt' => $receipt, 'notes' => $notes, 'demo' => true],
        );
    }

    public function verifySignature(string $orderId, string $paymentId, string $signature): bool
    {
        return hash_equals($this->sign($orderId, $paymentId), $signature);
    }

    /**
     * What the app sends back to prove "payment succeeded". Only the demo
     * gateway hands this out — with a real provider it comes from the provider.
     */
    public function sign(string $orderId, string $paymentId): string
    {
        return hash_hmac('sha256', "{$orderId}|{$paymentId}", $this->secret);
    }

    public function refund(string $paymentId, float $amountInRupees, string $reason): ?string
    {
        return 'rfnd_demo_' . Str::lower(Str::random(14));
    }

    public function publicKey(): string
    {
        return 'demo_key';
    }

    public function displayName(): string
    {
        return $this->displayName;
    }

    public function isDemo(): bool
    {
        return true;
    }
}
