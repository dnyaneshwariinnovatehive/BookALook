<?php

namespace App\Services\Payments;

/**
 * The seam an online payment provider plugs into.
 *
 * BookALook currently runs without one: the default binding is
 * NoPaymentGateway, bookings are confirmed straight away and the salon records
 * what it is paid (see BookingPaymentService::recordPayment). Everything that
 * an online provider would need — orders, signature verification, refunds,
 * the payment_orders / payments / payment_refunds tables — is kept, so a
 * provider can be added later by implementing this interface and binding it
 * in AppServiceProvider, without rebuilding the payment system.
 *
 * Scoped to customer appointment payments only. Salon subscriptions and
 * commission dues are paid by bank transfer and verified by SuperAdmin.
 */
interface PaymentGateway
{
    /**
     * Whether customers can pay online at all. False means bookings skip the
     * payment step and the salon collects in person.
     */
    public function isEnabled(): bool;

    /**
     * Open an order for [$amountInRupees]. The returned id is what the app
     * hands to the provider's checkout.
     *
     * @throws PaymentGatewayException when no order can be opened
     */
    public function createOrder(float $amountInRupees, string $receipt, array $notes = []): GatewayOrder;

    /**
     * Is this callback genuinely from the provider, for this order?
     *
     * Signature checking is the whole security model here: the client tells us
     * a payment succeeded, and only the signature makes that believable.
     */
    public function verifySignature(string $orderId, string $paymentId, string $signature): bool;

    /**
     * Send money back. Returns the provider's refund id, or null when it could
     * not be raised — the caller keeps the refund pending rather than
     * pretending it went through.
     */
    public function refund(string $paymentId, float $amountInRupees, string $reason): ?string;

    /** The publishable key the app needs to open checkout. */
    public function publicKey(): string;

    /** Name shown on the checkout sheet. */
    public function displayName(): string;
}
