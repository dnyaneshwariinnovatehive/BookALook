<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Appointment;
use App\Models\SalonWallet;
use App\Models\WalletScheme;
use App\Models\WalletTransaction;

class AppointmentController extends Controller
{
    public function index(Request $request, $salon_id)
    {
        $user = $request->user();

        // appointedProvider.user and services.service.template are what the
        // partner app shows and filters on.
        $query = Appointment::with([
                'customer',
                'appointedProvider.user',
                'servingProvider.user',
                'services.service.template',
                'serviceAdditions.service.template',
            ])
            ->where('salon_id', $salon_id)
            // Slots held while a customer is mid-payment block the time but are
            // not bookings yet — the salon should not see a customer who may
            // never pay.
            ->where('status', '!=', 'pending_payment');

        if ($user->role === 'service_provider') {
            $provider = \App\Models\ServiceProvider::where('user_id', $user->id)->first();
            if ($provider) {
                $query->where(function($q) use ($provider) {
                    $q->where('appointed_provider_id', $provider->id)
                      ->orWhere('serving_provider_id', $provider->id);
                });
            } else {
                return response()->json(['message' => 'You are not a registered service provider.'], 403);
            }
        } elseif (!in_array($user->role, ['admin', 'superadmin'])) {
            return response()->json(['message' => 'Unauthorized.'], 403);
        }

        if ($request->has('date') && !empty($request->date) && $request->date !== 'All') {
            $query->whereDate('appointment_date', $request->date);
        }

        if ($request->has('provider_id') && !empty($request->provider_id) && $request->provider_id !== 'All') {
            $query->where('appointed_provider_id', $request->provider_id);
        }

        if ($request->has('status') && !empty($request->status) && $request->status !== 'All') {
            $query->where('status', strtolower($request->status));
        }

        $appointments = $query->orderBy('start_time', 'asc')->get();
        return response()->json(['appointments' => $appointments]);
    }

    public function verifyQrAndStartSession(Request $request, $salon_id)
    {
        $request->validate(['qr_token' => 'required|string']);
        $provider = \App\Models\ServiceProvider::where('user_id', $request->user()->id)->first();
        
        $qrTokenHash = hash('sha256', $request->qr_token);
        $appointment = Appointment::where('salon_id', $salon_id)->where('qr_token_hash', $qrTokenHash)->first();

        if (!$appointment) return response()->json(['message' => 'Invalid QR Code.'], 404);
        if ($appointment->status !== 'scheduled') return response()->json(['message' => 'Not scheduled.'], 400);

        $earlyAllowance = (int) \App\Models\PlatformPolicySetting::value('appointment_start_early_minutes');
        $appointmentStart = \Carbon\Carbon::parse(
            \Carbon\Carbon::parse($appointment->appointment_date)->format('Y-m-d') . ' ' . $appointment->start_time
        );

        if (now()->addMinutes($earlyAllowance)->lessThan($appointmentStart)) {
            return response()->json(['message' => 'It is too early to start this appointment.'], 400);
        }

        $appointment->status = 'in_progress';
        $appointment->serving_provider_id = $provider->id; // Assign to whoever scanned
        $appointment->qr_verified_at = now();
        $appointment->qr_verified_by = $request->user()->id;
        $appointment->started_at = now();
        $appointment->save();

        return response()->json(['message' => 'Session started', 'appointment' => $appointment]);
    }

    public function markNoShow(Request $request, $id)
    {
        $appointment = Appointment::findOrFail($id);

        if ($denied = $this->denyUnlessSalonStaff($request, $appointment->salon_id)) {
            return $denied;
        }

        $appointment->status = 'no_show';
        $appointment->no_show_at = now();
        $appointment->save();

        return response()->json(['message' => 'Marked as no show.']);
    }

    /**
     * Finish an appointment and take the balance.
     *
     * Kept for callers that only have an appointment id. The work — commission
     * snapshots, the payment row, wallet coins — lives in
     * AppointmentCheckInService so this and the salon-scoped check-in endpoint
     * cannot drift apart.
     */
    public function complete(Request $request, $id)
    {
        $checkIn = app(\App\Services\AppointmentCheckInService::class);

        $appointment = Appointment::with($checkIn->relations())->findOrFail($id);

        if ($denied = $this->denyUnlessSalonStaff($request, $appointment->salon_id)) {
            return $denied;
        }

        if ($appointment->status === 'completed') {
            return response()->json(['message' => 'This appointment is already settled.'], 422);
        }

        $request->validate([
            'payment_mode' => 'nullable|in:' . implode(',', \App\Services\AppointmentCheckInService::PAYMENT_MODES),
        ]);

        $result = $checkIn->collectPaymentAndComplete(
            $appointment,
            $request->input('payment_mode', 'cash'),
            $request->user()
        );

        return response()->json([
            'success' => true,
            'message' => 'Appointment completed successfully.',
            'bill' => $result['bill'],
            'coins_earned_this_time' => $result['coins_earned'],
            'new_balance' => $result['new_balance'],
        ]);
    }

    /**
     * The salon's owner or one of its active staff. These endpoints move money
     * and appointment state, so knowing an id is not enough.
     */
    private function denyUnlessSalonStaff(Request $request, string $salonId)
    {
        $user = $request->user();

        if ($user->role === 'superadmin') {
            return null;
        }

        if ($user->role === 'admin'
            && \App\Models\Salon::where('id', $salonId)->where('admin_id', $user->id)->exists()) {
            return null;
        }

        if ($user->role === 'service_provider'
            && \App\Models\ServiceProvider::where('user_id', $user->id)
                ->where('salon_id', $salonId)
                ->where('is_active', true)
                ->exists()) {
            return null;
        }

        return response()->json(['message' => 'You do not work at this salon.'], 403);
    }
}
