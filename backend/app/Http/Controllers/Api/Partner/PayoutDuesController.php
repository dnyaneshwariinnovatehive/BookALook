<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\Salon;
use App\Models\SalonPayout;
use App\Services\PayoutDuesService;
use Illuminate\Http\Request;

/**
 * Paying BookALook: where to pay, and the owner's screenshot of paying what a
 * payout says the salon owes. Reachable while the salon is locked out — not
 * paying is exactly what locks a Commission Model salon out, so paying must
 * always work.
 */
class PayoutDuesController extends Controller
{
    public function __construct(private PayoutDuesService $dues)
    {
    }

    /** BookALook's payment QR, UPI ID and payee name, for any pay screen. */
    public function paymentDetails()
    {
        return response()->json(['success' => true] + $this->dues->paymentDetails());
    }

    public function submit(Request $request, $salonId, $payoutId)
    {
        $request->validate([
            'screenshot' => 'required|image|mimes:jpeg,png,jpg,webp|max:5120',
            'transaction_id' => 'nullable|string|max:150',
            'note' => 'nullable|string|max:1000',
        ]);

        $salon = Salon::where('id', $salonId)->where('admin_id', $request->user()->id)->first();
        if (! $salon) {
            return response()->json(['message' => 'Only the salon owner can pay for this salon.'], 403);
        }

        $payout = SalonPayout::where('id', $payoutId)->where('salon_id', $salon->id)->first();
        if (! $payout) {
            return response()->json(['message' => 'That payout does not belong to this salon.'], 404);
        }

        try {
            $submission = $this->dues->submit(
                $salon,
                $payout,
                $request->file('screenshot'),
                $request->input('transaction_id'),
                $request->input('note'),
                $request->user()
            );
        } catch (\RuntimeException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], 422);
        }

        return response()->json([
            'success' => true,
            'message' => 'Payment sent for verification. You will be notified once BookALook confirms it.',
            'payment_submission' => $submission->present(),
        ]);
    }
}
