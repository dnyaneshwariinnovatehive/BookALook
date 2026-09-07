<?php

namespace App\Services\Payments;

/**
 * The seam a real payment provider plugs into.
 *
 * Scoped to customer appointment advances only. Salon subscriptions are paid
 * by bank transfer and verified from a screenshot by SuperAdmin — that flow
 * deliberately does not come through here.
 */
interface PaymentGateway
{
    /**
     * Open an order for [$amountInRupees]. The returned id is what the app
     * hands to the checkout sheet.
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

    /**
     * True when no real money moves. The app shows its own confirm sheet
     * instead of the provider's, so the flow is exercised end to end without
     * live keys.
     */
    public function isDemo(): bool;
}
