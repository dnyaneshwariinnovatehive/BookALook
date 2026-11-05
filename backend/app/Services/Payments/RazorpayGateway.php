<?php

namespace App\Services\Payments;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Razorpay, over its REST API. Customer appointment payments only — salons
 * still pay subscriptions and commission dues by bank transfer with a photo
 * of the receipt.
 *
 * Deliberately no SDK: an order is one authenticated POST and a signature check
 * is one HMAC, so a dependency would be more surface area than it saves.
 *
 * Razorpay's fee is BookALook's cost: payouts are worked out from the gross
 * amount the customer paid, never from what Razorpay settles.
 */
class RazorpayGateway implements PaymentGateway
{
    private const BASE_URL = 'https://api.razorpay.com/v1';

    public function __construct(
        private string $keyId,
        private string $keySecret,
        private string $displayName,
        private string $webhookSecret = '',
    ) {
    }

    public function isEnabled(): bool
    {
        return $this->keyId !== '' && $this->keySecret !== '';
    }

    public function createOrder(float $amountInRupees, string $receipt, array $notes = []): GatewayOrder
    {
        // Razorpay works in paise; rounding here rather than anywhere else keeps
        // a rupee from being lost to floating point.
        $paise = (int) round($amountInRupees * 100);

        $response = Http::withBasicAuth($this->keyId, $this->keySecret)
            ->timeout(15)
            ->asJson()
            ->post(self::BASE_URL . '/orders', [
                'amount' => $paise,
                'currency' => 'INR',
                'receipt' => $receipt,
                'notes' => $notes,
                // The customer must not be able to part-pay what was asked.
                'partial_payment' => false,
                // Capture straight away, so a booking is never confirmed on
                // money Razorpay could still hand back on its own.
                'payment_capture' => 1,
            ]);

        if (! $response->successful()) {
            Log::error('Razorpay order creation failed', [
                'status' => $response->status(),
                'error' => $response->json('error.description'),
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
        if (! $this->isEnabled()) {
            return false;
        }

        // Constant time: a fast rejection would leak the secret a byte at a time.
        return hash_equals($this->checkoutSignature($orderId, $paymentId), $signature);
    }

    /**
     * The signature Razorpay's checkout hands the app for this order and
     * payment. The webhook uses it to confirm a payment through the same path
     * as the app, after proving the webhook itself came from Razorpay.
     */
    public function checkoutSignature(string $orderId, string $paymentId): string
    {
        return hash_hmac('sha256', "{$orderId}|{$paymentId}", $this->keySecret);
    }

    /** Is this webhook body genuinely from Razorpay? */
    public function verifyWebhook(string $body, string $signature): bool
    {
        if ($this->webhookSecret === '' || $signature === '') {
            return false;
        }

        return hash_equals(hash_hmac('sha256', $body, $this->webhookSecret), $signature);
    }

    public function refund(string $paymentId, float $amountInRupees, string $reason): ?string
    {
        $response = Http::withBasicAuth($this->keyId, $this->keySecret)
            ->timeout(15)
            ->asJson()
            ->post(self::BASE_URL . "/payments/{$paymentId}/refund", [
                'amount' => (int) round($amountInRupees * 100),
                'notes' => ['reason' => mb_substr($reason, 0, 250)],
            ]);

        if (! $response->successful()) {
            Log::warning('Razorpay refund failed', [
                'payment_id' => $paymentId,
                'error' => $response->json('error.description'),
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
}
