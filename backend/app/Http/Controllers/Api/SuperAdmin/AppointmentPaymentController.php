<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use App\Models\AuditLog;
use App\Services\AuditLogger;
use App\Services\BookingPaymentService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * SuperAdmin's view of money on a booking, with the same controls the salon
 * has: record a payment the customer made, and mark any refund returned —
 * including ones BookALook itself owes for payments taken online in the past.
 */
class AppointmentPaymentController extends Controller
{
    public function __construct(private BookingPaymentService $payments)
    {
    }

    public function show(string $id)
    {
        $appointment = Appointment::findOrFail($id);

        return response()->json(['success' => true] + $this->payments->ledger($appointment));
    }

    public function store(Request $request, string $id)
    {
        $data = $request->validate([
            'amount' => 'required|numeric|min:0.01|max:1000000',
            'type' => ['required', Rule::in(BookingPaymentService::MANUAL_TYPES)],
            'mode' => ['required', Rule::in(BookingPaymentService::MANUAL_MODES)],
            'reference' => 'nullable|string|max:150',
            'note' => 'nullable|string|max:255',
        ]);

        $appointment = Appointment::with('salon:id,name')->findOrFail($id);

        if (in_array($appointment->status, ['cancelled', 'no_show', 'pending_payment', 'rescheduled'], true)) {
            return response()->json(['success' => false, 'message' => 'Payments cannot be recorded on this booking.'], 422);
        }

        try {
            $paymentId = $this->payments->recordPayment(
                $appointment,
                (float) $data['amount'],
                $data['type'],
                $data['mode'],
                $request->user()->id,
                $data['note'] ?? null,
                $data['reference'] ?? null,
            );
        } catch (\InvalidArgumentException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], 422);
        }

        AuditLogger::record(
            action: AuditLog::BOOKING_PAYMENT_RECORDED,
            entity: $appointment,
            label: sprintf('%s booking', $appointment->salon->name ?? 'Salon'),
            after: ['amount' => (float) $data['amount'], 'type' => $data['type'], 'mode' => $data['mode']],
            metadata: ['payment_id' => $paymentId, 'appointment_id' => $appointment->id],
        );

        return response()->json([
            'success' => true,
            'message' => 'Payment recorded.',
        ] + $this->payments->ledger($appointment->fresh()), 201);
    }

    public function refundReturned(Request $request, string $id, string $refundId)
    {
        $appointment = Appointment::with('salon:id,name')->findOrFail($id);
        $refund = DB::table('payment_refunds')->where('id', $refundId)->where('appointment_id', $appointment->id)->first();

        if (! $refund) {
            abort(404);
        }

        $data = $request->validate(['reference' => 'nullable|string|max:150']);
        $this->payments->markRefundReturned($refundId, $request->user()->id, $data['reference'] ?? null);

        AuditLogger::record(
            action: AuditLog::BOOKING_REFUND_RETURNED,
            entity: $appointment,
            label: sprintf('%s booking', $appointment->salon->name ?? 'Salon'),
            after: ['amount' => (float) $refund->amount, 'reference' => $data['reference'] ?? null],
            metadata: ['refund_id' => $refundId, 'appointment_id' => $appointment->id],
        );

        return response()->json(['success' => true, 'message' => 'Refund marked as returned.'] + $this->payments->ledger($appointment));
    }
}
