<?php

namespace App\Services\Payments;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Razorpay, over its REST API.
 *
 * Deliberately no SDK: an order is one authenticated POST and a signature check
 * is one HMAC, so pulling in a dependency to do that would be more surface area
 * than it saves.
 */
class RazorpayGateway implements PaymentGateway
{
    private const BASE_URL = 'https://api.razorpay.com/v1';

    public function __construct(
        private string $keyId,
        private string $keySecret,
        private string $displayName,
    ) {
    }

    public function createOrder(float $amountInRupees, string $receipt, array $notes = []): GatewayOrder
    {
        // Razorpay works in paise; rounding here rather than anywhere else keeps
        // a rupee from being lost to floating point.
        $paise = (int) round($amountInRupees * 100);

        $response = Http::withBasicAuth($this->keyId, $this->keySecret)
            ->asJson()
            ->post(self::BASE_URL . '/orders', [
                'amount' => $paise,
                'currency' => 'INR',
                'receipt' => $receipt,
                'notes' => $notes,
                // The customer must not be able to part-pay an advance.
                'partial_payment' => false,
            ]);

        if (! $response->successful()) {
            Log::error('Razorpay order creation failed', [
                'status' => $response->status(),
                'body' => $response->body(),
            ]);

            throw new PaymentGatewayException(
                'Could not start the payment. Please try again in a moment.'
            );
        }

        $body = $response->json();

        return new GatewayOrder(
            id: $body['id'],
            amountInPaise: (int) $body['amount'],
            currency: $body['currency'] ?? 'INR',
            gateway: 'razorpay',
            raw: $body,
        );
    }

    public function verifySignature(string $orderId, string $paymentId, string $signature): bool
    {
        $expected = hash_hmac('sha256', "{$orderId}|{$paymentId}", $this->keySecret);

        // Constant time: a fast rejection would leak the secret a byte at a time.
        return hash_equals($expected, $signature);
    }

    public function refund(string $paymentId, float $amountInRupees, string $reason): ?string
    {
        $response = Http::withBasicAuth($this->keyId, $this->keySecret)
            ->asJson()
            ->post(self::BASE_URL . "/payments/{$paymentId}/refund", [
                'amount' => (int) round($amountInRupees * 100),
                'notes' => ['reason' => $reason],
            ]);

        if (! $response->successful()) {
            Log::warning('Razorpay refund failed', [
                'payment_id' => $paymentId,
                'body' => $response->body(),
            ]);

            return null;
        }

        return $response->json('id');
    }

    public function publicKey(): string
    {
        return $this->keyId;
    }

    public function displayName(): string
    {
        return $this->displayName;
    }

    public function isDemo(): bool
    {
        return false;
    }
}
