<?php

namespace Tests\Support;

use App\Services\Payments\GatewayOrder;
use App\Services\Payments\PaymentGateway;
use Illuminate\Support\Str;

/**
 * A stand-in online gateway, for tests of the online payment path.
 *
 * BookALook runs with no gateway today, but the order → pay → verify → confirm
 * flow (and its refund handling) is kept for a future provider. These tests
 * keep it honest: orders are minted locally and signatures are an HMAC the
 * test can produce, exactly as a real provider's would be verified.
 */
class FakePaymentGateway implements PaymentGateway
{
    public const SECRET = 'fake-gateway-secret';

    public function isEnabled(): bool
    {
        return true;
    }

    public function createOrder(float $amountInRupees, string $receipt, array $notes = []): GatewayOrder
    {
        return new GatewayOrder('order_fake_' . Str::lower(Str::random(14)), (int) round($amountInRupees * 100), 'INR', 'fake');
    }

    public function verifySignature(string $orderId, string $paymentId, string $signature): bool
    {
        return hash_equals($this->sign($orderId, $paymentId), $signature);
    }

    public function refund(string $paymentId, float $amountInRupees, string $reason): ?string
    {
        return 'rfnd_fake_' . Str::lower(Str::random(12));
    }

    public function publicKey(): string
    {
        return 'key_fake';
    }

    public function displayName(): string
    {
        return 'BookALook';
    }

    /** What the provider would hand the app on success. */
    public function sign(string $orderId, string $paymentId): string
    {
        return hash_hmac('sha256', $orderId . '|' . $paymentId, self::SECRET);
    }
}
