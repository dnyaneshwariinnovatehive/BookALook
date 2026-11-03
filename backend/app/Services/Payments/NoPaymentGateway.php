<?php

namespace App\Services\Payments;

/**
 * The default: no online payments.
 *
 * Bookings are confirmed without a payment step, the advance the booking
 * policy asks for is tracked as "due", and the salon (or SuperAdmin) records
 * whatever is actually paid. Refunds of money taken outside the app are
 * returned by hand and marked as such.
 *
 * Every method that would move money refuses rather than pretending, so a
 * stray call can never record a payment that did not happen.
 */
class NoPaymentGateway implements PaymentGateway
{
    public function __construct(private string $displayName = 'BookALook')
    {
    }

    public function isEnabled(): bool
    {
        return false;
    }

    public function createOrder(float $amountInRupees, string $receipt, array $notes = []): GatewayOrder
    {
        throw new PaymentGatewayException('Online payments are not available.');
    }

    public function verifySignature(string $orderId, string $paymentId, string $signature): bool
    {
        return false;
    }

    public function refund(string $paymentId, float $amountInRupees, string $reason): ?string
    {
        return null;
    }

    public function publicKey(): string
    {
        return '';
    }

    public function displayName(): string
    {
        return $this->displayName;
    }
}
