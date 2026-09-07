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
            ->where('salon_id', $salon_id);

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

    public function walkIn(Request $request, $salon_id)
    {
        $request->validate([
            'customer_name' => 'required|string',
            'customer_phone' => 'nullable|string',
            'gender' => 'nullable|in:Male,Female,Other',
            'start_time' => 'nullable|date_format:Y-m-d H:i:s',
            'services' => 'required|array',
            'services.*' => 'exists:services,id'
        ]);

        $provider = \App\Models\ServiceProvider::where('user_id', $request->user()->id)->first();
        if (!$provider) return response()->json(['message' => 'Not a service provider'], 403);

        $services = \App\Models\Service::whereIn('id', $request->services)->get();
        $totalAmount = $services->sum('price');
        $totalDuration = $services->sum('duration_minutes');
        
        $startTime = $request->start_time ? \Carbon\Carbon::parse($request->start_time) : now();
        $endTime = (clone $startTime)->addMinutes($totalDuration);
        $status = $request->start_time ? 'scheduled' : 'in_progress';
        $startedAt = $request->start_time ? null : now();

        \Illuminate\Support\Facades\DB::beginTransaction();
        try {
            $appointment = new Appointment([
                'salon_id' => $salon_id,
                'appointed_provider_id' => $provider->id,
                'serving_provider_id' => $request->start_time ? null : $provider->id, // If it's for later, serving provider is decided when they scan/start
                'booking_source' => 'walk_in',
                'walk_in_customer_name' => $request->customer_name,
                'walk_in_customer_phone' => $request->customer_phone,
                'walk_in_customer_gender' => $request->gender,
                'appointment_date' => $startTime->format('Y-m-d'),
                'start_time' => $startTime->format('H:i:s'),
                'end_time' => $endTime->format('H:i:s'),
                'status' => $status,
                'payment_option' => 'full_at_venue',
                'total_amount' => $totalAmount,
                'advance_amount' => 0,
                'balance_amount' => $totalAmount,
                'started_at' => $startedAt,
            ]);
            $appointment->save();

            foreach ($services as $service) {
                \App\Models\AppointmentService::create([
                    'appointment_id' => $appointment->id,
                    'service_id' => $service->id,
                    'serving_provider_id' => $startedAt ? $provider->id : null,
                    'price_at_booking' => $service->price,
                    'original_service_price' => $service->price,
                    'duration_minutes_at_booking' => $service->duration_minutes,
                    'line_status' => $status
                ]);
            }

            \Illuminate\Support\Facades\DB::commit();
            return response()->json(['message' => 'Walk-in created', 'appointment' => $appointment]);
        } catch (\Exception $e) {
            \Illuminate\Support\Facades\DB::rollBack();
            return response()->json(['error' => $e->getMessage()], 500);
        }
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

    public function addServiceMidAppointment(Request $request, $salon_id, $id)
    {
        $request->validate([
            'service_id' => 'required|exists:services,id',
            'provider_id' => 'required|exists:service_providers,id', // Can assign to a different provider
        ]);

        $appointment = Appointment::where('salon_id', $salon_id)->findOrFail($id);
        if ($appointment->status !== 'in_progress') {
            return response()->json(['message' => 'Can only add services to in-progress appointments.'], 400);
        }

        $service = \App\Models\Service::with('template')->findOrFail($request->service_id);

        \Illuminate\Support\Facades\DB::beginTransaction();
        try {
            \App\Models\AppointmentServiceAddition::create([
                'appointment_id' => $appointment->id,
                'service_id' => $service->id,
                'provider_id' => $request->provider_id,
                'added_by' => $request->user()->id,
                'price_at_addition' => $service->price,
                // Duration lives on the template, not the salon's service row.
                'duration_minutes_at_addition' => $service->template->estimated_duration_minutes
                    ?? \App\Services\AvailabilityService::SLOT_MINUTES,
                'status' => 'active'
            ]);

            $baseAmount = $appointment->services()->sum('price_at_booking');
            $additionsAmount = $appointment->serviceAdditions()->where('status', 'active')->sum('price_at_addition');
            
            $appointment->total_amount = $baseAmount + $additionsAmount;
            $appointment->balance_amount = $appointment->total_amount - $appointment->advance_amount;
            $appointment->save();

            \Illuminate\Support\Facades\DB::commit();
            return response()->json(['message' => 'Service added', 'appointment' => $appointment->load('serviceAdditions.service')]);
        } catch (\Exception $e) {
            \Illuminate\Support\Facades\DB::rollBack();
            return response()->json(['error' => $e->getMessage()], 500);
        }
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
