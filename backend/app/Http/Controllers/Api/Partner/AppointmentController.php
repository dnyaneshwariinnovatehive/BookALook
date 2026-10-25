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
                'firstTimeOffer:id,name,discount_type,discount_value,scope',
            ])
            ->where('salon_id', $salon_id)
            // Slots held while a customer is mid-payment block the time but are
            // not bookings yet â€” the salon should not see a customer who may
            // never pay. Also exclude rescheduled/awaiting_reschedule as they don't occupy slots.
            ->whereNotIn('status', ['pending_payment', 'rescheduled', 'awaiting_reschedule']);

        if ($user->role === 'service_provider') {
            $provider = \App\Models\ServiceProvider::where('user_id', $user->id)
                ->where('salon_id', $salon_id)
                ->first();
            if ($provider) {
                $query->where(function($q) use ($provider) {
                    $q->where('appointed_provider_id', $provider->id)
                      ->orWhere('serving_provider_id', $provider->id);
                });
            } else {
                return response()->json(['message' => 'You are not a registered service provider at this salon.'], 403);
            }
        } elseif (!in_array($user->role, ['admin', 'superadmin'])) {
            return response()->json(['message' => 'Unauthorized.'], 403);
        }

        if ($request->has('date') && !empty($request->date) && $request->date !== 'All') {
            $query->whereDate('appointment_date', $request->date);
        }

        if ($request->has('provider_id') && !empty($request->provider_id) && $request->provider_id !== 'All') {
            $pId = $request->provider_id;
            $query->where(function ($q) use ($pId) {
                $q->where('appointed_provider_id', $pId)
                  ->orWhere('serving_provider_id', $pId);
            });
        }

        if ($request->has('status') && !empty($request->status) && $request->status !== 'All') {
            $query->where('status', strtolower($request->status));
        }

        $appointments = $query->orderBy('start_time', 'asc')->get();

        // Add explicit is_rescheduled flag for the frontend UI tag
        $appointments->each(function ($appointment) {
            $appointment->is_rescheduled = !is_null($appointment->rescheduled_from_id);
        });

        return response()->json(['appointments' => $appointments]);
    }

    public function markNoShow(Request $request, $id)
    {
        $appointment = Appointment::findOrFail($id);

        if ($denied = $this->denyUnlessSalonStaff($request, $appointment->salon_id)) {
            return $denied;
        }

        // Only a booking that is still waiting can be missed, and only once its
        // time has come. Without this a salon could mark a 6 pm booking a
        // no-show at 10 am — or a completed or cancelled one — and keep the
        // advance.
        if ($appointment->status !== 'scheduled') {
            return response()->json([
                'message' => 'Only a booking that has not started can be marked as a no-show.',
            ], 422);
        }

        $startsAt = \Carbon\Carbon::parse(
            \Carbon\Carbon::parse($appointment->appointment_date)->format('Y-m-d') . ' ' . $appointment->start_time
        );

        if (now()->lessThan($startsAt)) {
            return response()->json([
                'message' => 'This booking has not started yet. It can be marked as a no-show from ' . $startsAt->format('h:i A') . '.',
            ], 422);
        }

        $appointment->status = 'no_show';
        $appointment->no_show_at = now();
        $appointment->save();

        return response()->json(['message' => 'Marked as no show.']);
    }

    /**
     * Finish an appointment and take the balance.
     *
     * Kept for callers that only have an appointment id. The work â€” commission
     * snapshots, the payment row, wallet coins â€” lives in
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

        // Same rule as the check-in screen: only a session that was started —
        // the customer actually checked in — can be finished and billed. This
        // used to complete anything, including cancelled-and-refunded,
        // no-show and unpaid bookings.
        if ($appointment->status !== 'in_progress') {
            return response()->json([
                'message' => 'Start the appointment before completing it.',
            ], 422);
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
