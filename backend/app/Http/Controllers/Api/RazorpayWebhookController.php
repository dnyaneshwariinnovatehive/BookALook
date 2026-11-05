<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use App\Services\BookingPaymentService;
use App\Services\Payments\PaymentGateway;
use App\Services\Payments\RazorpayGateway;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Razorpay's server-to-server notice that a payment was captured.
 *
 * The safety net for a customer who paid but whose app never came back to
 * confirm (closed, killed, lost signal). The webhook body is proven genuine by
 * X-Razorpay-Signature, then the booking is confirmed through exactly the same
 * BookingPaymentService::confirm() the app uses — so it is idempotent, and a
 * payment that lands after the hold lapsed is refunded the same way.
 *
 * Always answers 200 once the signature checks out: Razorpay retries anything
 * else, and a retry cannot fix a booking that is already settled or refunded.
 */
class RazorpayWebhookController extends Controller
{
    public function __construct(
        private PaymentGateway $gateway,
        private BookingPaymentService $payments,
    ) {
    }

    public function handle(Request $request)
    {
        if (! $this->gateway instanceof RazorpayGateway) {
            return response()->json(['message' => 'Not configured.'], 404);
        }

        $body = $request->getContent();

        if (! $this->gateway->verifyWebhook($body, (string) $request->header('X-Razorpay-Signature', ''))) {
            Log::warning('Razorpay webhook rejected: bad signature');

            return response()->json(['message' => 'Invalid signature.'], 401);
        }

        $event = (string) $request->input('event');

        if (! in_array($event, ['payment.captured', 'order.paid'], true)) {
            return response()->json(['ok' => true, 'ignored' => $event]);
        }

        $payment = $request->input('payload.payment.entity', []);
        $paymentId = (string) ($payment['id'] ?? '');
        $orderId = (string) ($payment['order_id'] ?? '');

        if ($paymentId === '' || $orderId === '') {
            return response()->json(['ok' => true, 'ignored' => 'no payment']);
        }

        $order = DB::table('payment_orders')
            ->where('gateway', 'razorpay')
            ->where('gateway_order_id', $orderId)
            ->first();

        $appointment = $order ? Appointment::find($order->appointment_id) : null;

        if (! $appointment) {
            Log::warning('Razorpay webhook: no booking for order', ['order_id' => $orderId]);

            return response()->json(['ok' => true, 'ignored' => 'unknown order']);
        }

        try {
            $result = $this->payments->confirm(
                $appointment,
                $paymentId,
                $this->gateway->checkoutSignature($orderId, $paymentId),
                (string) $appointment->customer_id,
            );
        } catch (\Throwable $e) {
            report($e);

            // Worth a retry: the failure was ours, not the payment's.
            return response()->json(['message' => 'Could not record the payment.'], 500);
        }

        if (! ($result['ok'] ?? false) && empty($result['hold_expired'])) {
            // Money was taken but the booking could not take it — someone
            // has to look. Logged without the customer's details.
            Log::error('Razorpay webhook: captured payment not applied', [
                'appointment_id' => $appointment->id,
                'order_id' => $orderId,
                'payment_id' => $paymentId,
                'reason' => $result['message'] ?? null,
            ]);
        }

        return response()->json(['ok' => true]);
    }
}
