<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Services\BookingPaymentService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * Money on a booking, as the salon records it.
 *
 * With no online gateway the customer pays the salon — the advance before the
 * visit, the rest at the counter — and the salon records it here so the
 * booking shows paid, partly paid or unpaid. Refunds of money the salon took
 * are returned by the salon and marked returned here.
 *
 * Owner and staff may record payments; only the owner may mark a refund
 * returned, since that is money leaving the salon.
 */
class AppointmentPaymentController extends Controller
{
    public function __construct(private BookingPaymentService $payments)
    {
    }

    public function show(Request $request, string $salonId, string $id)
    {
        if ($denied = $this->deny($request, $salonId)) {
            return $denied;
        }

        $appointment = Appointment::where('salon_id', $salonId)->findOrFail($id);

        return response()->json(['success' => true] + $this->payments->ledger($appointment));
    }

    public function store(Request $request, string $salonId, string $id)
    {
        if ($denied = $this->deny($request, $salonId)) {
            return $denied;
        }

        $data = $request->validate([
            'amount' => 'required|numeric|min:0.01|max:1000000',
            'type' => ['required', Rule::in(BookingPaymentService::MANUAL_TYPES)],
            'mode' => ['required', Rule::in(BookingPaymentService::MANUAL_MODES)],
            'reference' => 'nullable|string|max:150',
            'note' => 'nullable|string|max:255',
        ]);

        $appointment = Appointment::where('salon_id', $salonId)->findOrFail($id);

        if (in_array($appointment->status, ['cancelled', 'no_show', 'pending_payment', 'rescheduled'], true)) {
            return response()->json(['success' => false, 'message' => 'Payments cannot be recorded on this booking.'], 422);
        }

        try {
            $this->payments->recordPayment(
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

        return response()->json([
            'success' => true,
            'message' => 'Payment recorded.',
        ] + $this->payments->ledger($appointment->fresh()), 201);
    }

    /** The salon has given a customer back money it took in person. */
    public function refundReturned(Request $request, string $salonId, string $id, string $refundId)
    {
        $user = $request->user();
        $isOwner = $user->role === 'superadmin'
            || ($user->role === 'admin' && Salon::where('id', $salonId)->where('admin_id', $user->id)->exists());

        if (! $isOwner) {
            return response()->json(['message' => 'Only the salon owner can mark a refund returned.'], 403);
        }

        $appointment = Appointment::where('salon_id', $salonId)->findOrFail($id);
        $refund = DB::table('payment_refunds')->where('id', $refundId)->where('appointment_id', $appointment->id)->first();

        if (! $refund) {
            abort(404);
        }

        $meta = json_decode($refund->metadata ?? '{}', true) ?: [];
        if (($meta['returned_by'] ?? null) !== 'salon') {
            return response()->json(['success' => false, 'message' => 'BookALook returns this refund, not the salon.'], 422);
        }

        $data = $request->validate(['reference' => 'nullable|string|max:150']);
        $this->payments->markRefundReturned($refundId, $user->id, $data['reference'] ?? null);

        return response()->json(['success' => true, 'message' => 'Refund marked as returned.'] + $this->payments->ledger($appointment));
    }

    private function deny(Request $request, string $salonId)
    {
        $user = $request->user();

        if ($user->role === 'superadmin') {
            return null;
        }
        if ($user->role === 'admin' && Salon::where('id', $salonId)->where('admin_id', $user->id)->exists()) {
            return null;
        }
        if ($user->role === 'service_provider'
            && ServiceProvider::where('user_id', $user->id)->where('salon_id', $salonId)->where('is_active', true)->exists()) {
            return null;
        }

        return response()->json(['message' => 'You do not work at this salon.'], 403);
    }
}
