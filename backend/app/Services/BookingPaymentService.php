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
     * @return array{ok: bool, message: ?string, hold_expired?: bool, refunded?: bool, refund_id?: ?string, already_confirmed?: bool, recommitted?: bool}
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
            $existingApp = Appointment::find($appointment->id);
            if ($existingApp && $existingApp->status === 'cancelled') {
                $refundRecord = DB::table('payment_refunds')
                    ->where('appointment_id', $appointment->id)
                    ->orderByDesc('created_at')
                    ->first();

                if ($refundRecord) {
                    if ($refundRecord->status === 'processed') {
                        return [
                            'ok' => false,
                            'hold_expired' => true,
                            'reconciled' => false,
                            'refunded' => true,
                            'already_refunded' => true,
                            'refund_id' => $refundRecord->gateway_refund_id,
                            'message' => 'The hold on your slot expired and the offer could not be applied. Your payment was already refunded.',
                        ];
                    }

                    // Retry pending refund outside transaction
                    $retryResult = $this->processPendingRefund($refundRecord->id);

                    return [
                        'ok' => false,
                        'hold_expired' => true,
                        'reconciled' => false,
                        'refunded' => $retryResult['success'],
                        'refund_pending' => ! $retryResult['success'],
                        'refund_id' => $retryResult['refund_id'] ?? null,
                        'message' => $retryResult['success']
                            ? 'The hold on your slot expired and the offer could not be applied. Your payment has been refunded.'
                            : 'The hold on your slot expired and the offer could not be applied. Your refund is pending.',
                    ];
                }
            }

            // A retried callback must not charge or book twice.
            return ['ok' => true, 'already_confirmed' => true, 'message' => 'This payment was already confirmed.'];
        }

        // Cryptographic signature verification outside database locks
        if (! $this->gateway->verifySignature($order->gateway_order_id, $gatewayPaymentId, $signature)) {
            return ['ok' => false, 'message' => 'That payment could not be verified.'];
        }

        $txResult = DB::transaction(function () use ($appointment, $order, $gatewayPaymentId, $signature, $actorId) {
            // Consistent locking order:
            // 1. Lock Appointment
            $lockedApp = Appointment::where('id', $appointment->id)->lockForUpdate()->first();
            if (! $lockedApp) {
                return ['ok' => false, 'message' => 'Appointment not found.'];
            }

            // 2. Lock Offer (if appointment is associated with a first-time offer)
            $offer = null;
            if ($lockedApp->first_time_offer_id) {
                $offer = \App\Models\FirstTimeOffer::where('id', $lockedApp->first_time_offer_id)->lockForUpdate()->first();
            }

            // 3. Lock Redemption (if redemption exists for this appointment)
            $redemption = \App\Models\FirstTimeOfferRedemption::where('appointment_id', $lockedApp->id)->lockForUpdate()->first();

            // 4. Re-check order status inside transaction (idempotency under concurrent callbacks)
            $freshOrder = DB::table('payment_orders')->where('id', $order->id)->lockForUpdate()->first();
            if ($freshOrder->status === 'paid') {
                if ($lockedApp->status === 'cancelled') {
                    $refundRecord = DB::table('payment_refunds')
                        ->where('appointment_id', $lockedApp->id)
                        ->orderByDesc('created_at')
                        ->first();

                    if ($refundRecord) {
                        return [
                            'action' => 'already_refunded_or_pending',
                            'refund_record_id' => $refundRecord->id,
                            'status' => $refundRecord->status,
                            'gateway_refund_id' => $refundRecord->gateway_refund_id,
                        ];
                    }
                }

                return ['ok' => true, 'already_confirmed' => true, 'message' => 'This payment was already confirmed.'];
            }

            // DB-level idempotency key protects against duplicate payment insertions
            $existingPayment = DB::table('payments')
                ->where('idempotency_key', 'advance:' . $lockedApp->id)
                ->first();

            $paymentRecordId = $existingPayment?->id ?? (string) Str::uuid();

            if (! $existingPayment) {
                DB::table('payments')->insert([
                    'id' => $paymentRecordId,
                    'appointment_id' => $lockedApp->id,
                    'payment_order_id' => $freshOrder->id,
                    'amount' => $freshOrder->amount,
                    'currency' => $freshOrder->currency,
                    'payment_type' => $this->paymentType($lockedApp, (float) $freshOrder->amount),
                    'payment_mode' => 'online',
                    'gateway' => $freshOrder->gateway,
                    'gateway_transaction_id' => $gatewayPaymentId,
                    'gateway_signature' => $signature,
                    'status' => 'success',
                    'paid_at' => now(),
                    'idempotency_key' => 'advance:' . $lockedApp->id,
                    'metadata' => json_encode(['confirmed_by' => $actorId]),
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }

            DB::table('payment_orders')
                ->where('id', $freshOrder->id)
                ->update(['status' => 'paid', 'updated_at' => now()]);

            // Handle First-Time Offer Redemption & Appointment State Reconciliation
            if ($redemption) {
                if ($redemption->status === \App\Models\FirstTimeOfferRedemption::STATUS_RESERVED) {
                    // Normal path: reservation was active, commit it
                    $redemption->commit();

                    $lockedApp->forceFill([
                        'status' => 'scheduled',
                        'cancelled_by' => null,
                        'cancelled_by_user_id' => null,
                        'cancellation_reason' => null,
                        'cancelled_at' => null,
                        'payment_hold_expires_at' => null,
                    ])->save();

                    $lockedApp->services()->update(['line_status' => 'confirmed']);

                    return ['ok' => true, 'message' => null];
                }

                if ($redemption->status === \App\Models\FirstTimeOfferRedemption::STATUS_COMMITTED) {
                    // Already committed (duplicate callback)
                    return ['ok' => true, 'already_confirmed' => true, 'message' => 'This payment was already confirmed.'];
                }

                if ($redemption->status === \App\Models\FirstTimeOfferRedemption::STATUS_RELEASED) {
                    // Expiration won the earlier race, but payment genuinely succeeded at the gateway.
                    // Deterministically evaluate whether we can safely recommit the reservation:
                    $canRecommit = false;
                    $rejectionReason = null;

                    if (! $offer || ! $offer->is_active || ! $offer->isCurrentlyValid()) {
                        $rejectionReason = 'The promotional offer has expired or is no longer active.';
                    } elseif ($offer->max_redemptions !== null && (int) $offer->current_redemptions >= (int) $offer->max_redemptions) {
                        $rejectionReason = 'The promotional offer reached its maximum redemption capacity.';
                    } else {
                        // Check if the customer has committed this offer elsewhere
                        $customer = $lockedApp->customer ?? \App\Models\User::find($lockedApp->customer_id);
                        $phoneHash = $lockedApp->customer_phone_hash ?? \App\Models\FirstTimeOffer::hashPhone($customer?->phone);

                        $hasOtherCommitted = \App\Models\FirstTimeOfferRedemption::where('offer_id', $offer->id)
                            ->where('status', \App\Models\FirstTimeOfferRedemption::STATUS_COMMITTED)
                            ->where('appointment_id', '!=', $lockedApp->id)
                            ->where(function ($q) use ($lockedApp, $phoneHash) {
                                $q->where('customer_id', $lockedApp->customer_id);
                                if ($phoneHash) {
                                    $q->orWhere('customer_phone_hash', $phoneHash);
                                }
                            })
                            ->exists();

                        if ($hasOtherCommitted) {
                            $rejectionReason = 'This promotional offer has already been redeemed on another booking.';
                        } else {
                            $canRecommit = true;
                        }
                    }

                    if ($canRecommit) {
                        // Safely recommit reservation and increment campaign accounting
                        $customer = $lockedApp->customer ?? \App\Models\User::find($lockedApp->customer_id);
                        $entitlementKey = $offer->makeEntitlementKey($customer ?? $lockedApp->customer_id, $lockedApp->salon_id);
                        $redemption->recommit($entitlementKey);

                        $lockedApp->forceFill([
                            'status' => 'scheduled',
                            'cancelled_by' => null,
                            'cancelled_by_user_id' => null,
                            'cancellation_reason' => null,
                            'cancelled_at' => null,
                            'payment_hold_expires_at' => null,
                        ])->save();

                        $lockedApp->services()->update(['line_status' => 'confirmed']);

                        return [
                            'ok' => true,
                            'recommitted' => true,
                            'message' => 'Payment received. Your appointment is confirmed.',
                        ];
                    }

                    // Cannot safely recommit (capacity exhausted or offer claimed elsewhere).
                    // Safe, durable recovery: create pending refund record in DB first, keep redemption released, keep appointment cancelled.
                    $refundRecordId = (string) Str::uuid();

                    DB::table('payment_refunds')->insert([
                        'id' => $refundRecordId,
                        'payment_id' => $paymentRecordId,
                        'appointment_id' => $lockedApp->id,
                        'amount' => (float) $freshOrder->amount,
                        'reason' => 'Hold expired and offer is no longer available: ' . $rejectionReason,
                        'gateway_refund_id' => null,
                        'status' => 'pending',
                        'initiated_by' => $actorId,
                        'metadata' => json_encode([
                            'idempotency_key' => "refund:{$paymentRecordId}",
                            'rejection_reason' => $rejectionReason,
                            'gateway_payment_id' => $gatewayPaymentId,
                        ]),
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);

                    DB::table('payments')
                        ->where('id', $paymentRecordId)
                        ->update([
                            'metadata' => json_encode([
                                'confirmed_by' => $actorId,
                                'reconciliation_failed' => true,
                                'rejection_reason' => $rejectionReason,
                                'refund_record_id' => $refundRecordId,
                                'refund_id' => null,
                                'refund_status' => 'pending',
                            ]),
                        ]);

                    return [
                        'action' => 'refund_required',
                        'refund_record_id' => $refundRecordId,
                        'payment_record_id' => $paymentRecordId,
                        'rejection_reason' => $rejectionReason,
                        'amount' => (float) $freshOrder->amount,
                    ];
                }
            }

            // Regular booking without first-time offer
            if ($lockedApp->status === 'cancelled') {
                $lockedApp->forceFill([
                    'status' => 'scheduled',
                    'cancelled_by' => null,
                    'cancelled_by_user_id' => null,
                    'cancellation_reason' => null,
                    'cancelled_at' => null,
                    'payment_hold_expires_at' => null,
                ])->save();

                $lockedApp->services()->update(['line_status' => 'confirmed']);

                return ['ok' => true, 'reinstated' => true, 'message' => null];
            }

            $lockedApp->forceFill([
                'status' => 'scheduled',
                'payment_hold_expires_at' => null,
            ])->save();

            $lockedApp->services()->update(['line_status' => 'confirmed']);

            return ['ok' => true, 'message' => null];
        });

        if (isset($txResult['action'])) {
            if ($txResult['action'] === 'refund_required') {
                $processResult = $this->processPendingRefund($txResult['refund_record_id']);

                return [
                    'ok' => false,
                    'hold_expired' => true,
                    'reconciled' => false,
                    'refunded' => $processResult['success'],
                    'refund_pending' => ! $processResult['success'],
                    'refund_id' => $processResult['refund_id'] ?? null,
                    'message' => $processResult['success']
                        ? "The hold on your slot expired and the offer could not be applied ({$txResult['rejection_reason']}). Your payment has been refunded."
                        : "The hold on your slot expired and the offer could not be applied ({$txResult['rejection_reason']}). Your payment has been recorded and your refund is pending.",
                ];
            }

            if ($txResult['action'] === 'already_refunded_or_pending') {
                if ($txResult['status'] === 'processed') {
                    return [
                        'ok' => false,
                        'hold_expired' => true,
                        'reconciled' => false,
                        'refunded' => true,
                        'already_refunded' => true,
                        'refund_id' => $txResult['gateway_refund_id'],
                        'message' => 'The hold on your slot expired and the offer could not be applied. Your payment was already refunded.',
                    ];
                }

                $retryResult = $this->processPendingRefund($txResult['refund_record_id']);

                return [
                    'ok' => false,
                    'hold_expired' => true,
                    'reconciled' => false,
                    'refunded' => $retryResult['success'],
                    'refund_pending' => ! $retryResult['success'],
                    'refund_id' => $retryResult['refund_id'] ?? null,
                    'message' => $retryResult['success']
                        ? 'The hold on your slot expired and the offer could not be applied. Your payment has been refunded.'
                        : 'The hold on your slot expired and the offer could not be applied. Your refund is pending.',
                ];
            }
        }

        return $txResult;
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
            ->whereIn('status', ['created', 'paid', 'abandoned'])
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
    public function release(Appointment $appointment, string $reason): bool
    {
        return DB::transaction(function () use ($appointment, $reason) {
            $lockedApp = Appointment::where('id', $appointment->id)->lockForUpdate()->first();
            if (! $lockedApp) {
                return false;
            }

            // An expiration worker must not cancel or release a booking after successful payment has been verified or scheduled.
            if ($lockedApp->status === 'scheduled') {
                return false;
            }

            $hasPaidOrder = DB::table('payment_orders')
                ->where('appointment_id', $lockedApp->id)
                ->where('status', 'paid')
                ->exists();
            if ($hasPaidOrder) {
                return false;
            }

            $hasSuccessPayment = DB::table('payments')
                ->where('appointment_id', $lockedApp->id)
                ->where('status', 'success')
                ->exists();
            if ($hasSuccessPayment) {
                return false;
            }

            DB::table('payment_orders')
                ->where('appointment_id', $lockedApp->id)
                ->where('status', 'created')
                ->update(['status' => 'abandoned', 'updated_at' => now()]);

            // Cancelled rather than deleted: an abandoned checkout is still
            // something the salon may want to see.
            $lockedApp->forceFill([
                'status' => 'cancelled',
                'cancelled_by' => 'system',
                'cancellation_reason' => $reason,
                'cancelled_at' => now(),
            ])->save();

            $lockedApp->services()->update(['line_status' => 'cancelled']);

            // Release any active first-time offer reservation
            $redemption = \App\Models\FirstTimeOfferRedemption::where('appointment_id', $lockedApp->id)
                ->where('status', \App\Models\FirstTimeOfferRedemption::STATUS_RESERVED)
                ->lockForUpdate()
                ->first();

            if ($redemption) {
                $redemption->release($reason);
            }

            return true;
        });
    }

    /**
     * Give back every slot whose payment hold has run out.
     */
    public function releaseExpiredHolds(): int
    {
        $staleIds = Appointment::where('status', 'pending_payment')
            ->whereNotNull('payment_hold_expires_at')
            ->where('payment_hold_expires_at', '<', now())
            ->pluck('id');

        $releasedCount = 0;
        foreach ($staleIds as $id) {
            $app = Appointment::find($id);
            if ($app && $this->release($app, 'Payment was not completed in time.')) {
                $releasedCount++;
            }
        }

        return $releasedCount;
    }

    /**
     * Process a pending refund outside of any database transaction locks.
     *
     * Uses atomic CAS on payment_refunds (status pending -> processing)
     * so that concurrent callers or background reconciliation jobs cannot
     * call the external gateway simultaneously for the same refund.
     *
     * @return array{success: bool, refund_id?: ?string, already_processed?: bool, error?: ?string}
     */
    public function processPendingRefund(string $refundRecordId): array
    {
        $refund = DB::table('payment_refunds')->where('id', $refundRecordId)->first();
        if (! $refund) {
            return ['success' => false, 'error' => 'Refund record not found.'];
        }

        if ($refund->status === 'processed') {
            return [
                'success' => true,
                'already_processed' => true,
                'refund_id' => $refund->gateway_refund_id,
            ];
        }

        // Atomic check-and-claim: only transition if still pending
        $claimed = DB::table('payment_refunds')
            ->where('id', $refundRecordId)
            ->where('status', 'pending')
            ->update([
                'status' => 'processing',
                'updated_at' => now(),
            ]);

        if ($claimed === 0) {
            // Another worker claimed it or it transitioned already
            $fresh = DB::table('payment_refunds')->where('id', $refundRecordId)->first();

            return [
                'success' => $fresh?->status === 'processed',
                'already_processed' => $fresh?->status === 'processed',
                'refund_id' => $fresh?->gateway_refund_id,
            ];
        }

        $payment = DB::table('payments')->where('id', $refund->payment_id)->first();
        $gatewayPaymentId = $payment?->gateway_transaction_id;

        if (! $gatewayPaymentId) {
            DB::table('payment_refunds')
                ->where('id', $refundRecordId)
                ->update([
                    'status' => 'failed',
                    'failure_reason' => 'Missing gateway payment ID.',
                    'updated_at' => now(),
                ]);

            return ['success' => false, 'error' => 'Missing gateway payment ID.'];
        }

        // Network call outside any database transaction
        $gatewayRefundId = $this->refund(
            $gatewayPaymentId,
            (float) $refund->amount,
            $refund->reason
        );

        if ($gatewayRefundId !== null) {
            DB::table('payment_refunds')
                ->where('id', $refundRecordId)
                ->update([
                    'status' => 'processed',
                    'gateway_refund_id' => $gatewayRefundId,
                    'processed_at' => now(),
                    'failure_reason' => null,
                    'updated_at' => now(),
                ]);

            if ($payment) {
                $meta = json_decode($payment->metadata ?? '{}', true) ?: [];
                $meta['refund_id'] = $gatewayRefundId;
                $meta['refund_status'] = 'processed';

                DB::table('payments')
                    ->where('id', $payment->id)
                    ->update([
                        'metadata' => json_encode($meta),
                        'updated_at' => now(),
                    ]);
            }

            return ['success' => true, 'refund_id' => $gatewayRefundId];
        }

        // Gateway call timed out or returned error: retain durable pending status for reconciliation
        DB::table('payment_refunds')
            ->where('id', $refundRecordId)
            ->update([
                'status' => 'pending',
                'failure_reason' => 'Gateway refund request timed out or returned an error. Kept pending for reconciliation retry.',
                'updated_at' => now(),
            ]);

        if ($payment) {
            $meta = json_decode($payment->metadata ?? '{}', true) ?: [];
            $meta['refund_status'] = 'pending_retry';

            DB::table('payments')
                ->where('id', $payment->id)
                ->update([
                    'metadata' => json_encode($meta),
                    'updated_at' => now(),
                ]);
        }

        return ['success' => false, 'error' => 'Gateway refund failed or timed out.'];
    }

    /**
     * Sweep through pending payment refunds and attempt recovery.
     */
    public function reconcilePendingRefunds(): int
    {
        $pendingRefunds = DB::table('payment_refunds')
            ->where('status', 'pending')
            ->orderBy('created_at')
            ->get();

        $recovered = 0;
        foreach ($pendingRefunds as $pending) {
            $result = $this->processPendingRefund($pending->id);
            if (! empty($result['success'])) {
                $recovered++;
            }
        }

        return $recovered;
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
