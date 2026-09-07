<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use App\Models\AppointmentServiceAddition;
use App\Models\Salon;
use App\Models\Service;
use App\Models\ServiceProvider;
use App\Services\AppointmentCheckInService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

/**
 * Check a customer in, then take payment when they leave.
 *
 * Scanning is deliberately split into "resolve" and "start": the admin needs to
 * see who is booked, and be able to hand the job to a different staff member,
 * before anything is written.
 */
class CheckInController extends Controller
{
    public function __construct(private AppointmentCheckInService $checkIn)
    {
    }

    /**
     * Turn a scanned QR token (or a chosen appointment id, when staff are
     * checking someone in by hand) into everything the confirm screen needs.
     * Writes nothing.
     */
    public function resolve(Request $request, $salonId)
    {
        if ($denied = $this->denyUnlessSalonStaff($request, $salonId)) {
            return $denied;
        }

        $validator = Validator::make($request->all(), [
            'qr_token' => 'required_without:appointment_id|string',
            'appointment_id' => 'required_without:qr_token|string',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $appointment = $request->filled('qr_token')
            ? $this->checkIn->findByToken($salonId, $request->qr_token)
            : Appointment::with($this->checkIn->relations())
                ->where('salon_id', $salonId)
                ->find($request->appointment_id);

        if (! $appointment) {
            return response()->json([
                'message' => $request->filled('qr_token')
                    ? 'This QR code does not belong to any booking at this salon.'
                    : 'Appointment not found at this salon.',
            ], 404);
        }

        return response()->json([
            'appointment' => $this->present($appointment),
            'bill' => $this->checkIn->bill($appointment),
            'providers' => $this->checkIn->providerOptions($appointment),
            'default_serving_provider_id' => $appointment->serving_provider_id
                ?? $appointment->appointed_provider_id,
            'can_start' => $this->checkIn->blockedReason($appointment) === null,
            'blocked_reason' => $this->checkIn->blockedReason($appointment),
        ]);
    }

    /**
     * Start the session, optionally under a different staff member than the one
     * the customer booked.
     */
    public function start(Request $request, $salonId, $appointmentId)
    {
        if ($denied = $this->denyUnlessSalonStaff($request, $salonId)) {
            return $denied;
        }

        $validator = Validator::make($request->all(), [
            'serving_provider_id' => 'nullable|exists:service_providers,id',
            'qr_token' => 'nullable|string',
            // Staff may start without a scan (dead phone, damaged screen). It is
            // recorded as a manual check-in rather than pretending a QR was seen.
            'manual' => 'boolean',
            'reason' => 'nullable|string|max:255',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $appointment = Appointment::with($this->checkIn->relations())
            ->where('salon_id', $salonId)
            ->findOrFail($appointmentId);

        if ($reason = $this->checkIn->blockedReason($appointment)) {
            return response()->json(['message' => $reason], 422);
        }

        $isManual = $request->boolean('manual') || ! $request->filled('qr_token');

        // A token was offered — it has to actually match this booking.
        if ($request->filled('qr_token')) {
            $matched = $this->checkIn->findByToken($salonId, $request->qr_token);

            if (! $matched || $matched->id !== $appointment->id) {
                return response()->json(['message' => 'That QR code is for a different booking.'], 422);
            }

            $isManual = false;
        }

        $servingProviderId = $request->input('serving_provider_id')
            ?? $appointment->appointed_provider_id;

        if (! $this->providerBelongsToSalon($servingProviderId, $salonId)) {
            return response()->json(['message' => 'That staff member does not work at this salon.'], 422);
        }

        $appointment = $this->checkIn->start(
            $appointment,
            $servingProviderId,
            $request->user(),
            $isManual ? AppointmentCheckInService::VERIFY_MANUAL : AppointmentCheckInService::VERIFY_QR,
            $request->input('reason')
        );

        return response()->json([
            'message' => 'Session started.',
            'appointment' => $this->present($appointment),
            'bill' => $this->checkIn->bill($appointment),
        ]);
    }

    /**
     * Add a service to an appointment that is already under way.
     *
     * The customer agreed in the chair, so no digital approval is collected.
     * The provider delivering the extra is chosen explicitly and defaults to
     * whoever is serving — picking someone else is the whole point when two
     * staff contribute to one appointment.
     */
    public function addService(Request $request, $salonId, $appointmentId)
    {
        if ($denied = $this->denyUnlessSalonStaff($request, $salonId)) {
            return $denied;
        }

        $validator = Validator::make($request->all(), [
            'service_id' => 'required|string|exists:services,id',
            'provider_id' => 'nullable|exists:service_providers,id',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $appointment = Appointment::with($this->checkIn->relations())
            ->where('salon_id', $salonId)
            ->findOrFail($appointmentId);

        if ($appointment->status !== 'in_progress') {
            return response()->json([
                'message' => 'Extras can only be added while the appointment is in progress.',
            ], 422);
        }

        // The service has to be this salon's, or another salon's price would
        // land on this bill.
        $service = Service::with('template')
            ->where('salon_id', $salonId)
            ->find($request->service_id);

        if (! $service) {
            return response()->json(['message' => 'That service is not offered by this salon.'], 422);
        }

        $providerId = $request->input('provider_id')
            ?? $appointment->serving_provider_id
            ?? $appointment->appointed_provider_id;

        if (! $this->providerBelongsToSalon($providerId, $salonId)) {
            return response()->json(['message' => 'That staff member does not work at this salon.'], 422);
        }

        $this->checkIn->addExtraService($appointment, $service, $providerId, $request->user());

        $appointment = $appointment->fresh($this->checkIn->relations());

        return response()->json([
            'message' => "{$service->template->name} added to the bill.",
            'appointment' => $this->present($appointment),
            'bill' => $this->checkIn->bill($appointment),
        ], 201);
    }

    /**
     * Take an extra back off the bill. Voided rather than deleted so the record
     * can still explain itself.
     */
    public function removeService(Request $request, $salonId, $appointmentId, $additionId)
    {
        if ($denied = $this->denyUnlessSalonStaff($request, $salonId)) {
            return $denied;
        }

        $appointment = Appointment::with($this->checkIn->relations())
            ->where('salon_id', $salonId)
            ->findOrFail($appointmentId);

        if ($appointment->status !== 'in_progress') {
            return response()->json([
                'message' => 'The bill can only be changed while the appointment is in progress.',
            ], 422);
        }

        $addition = AppointmentServiceAddition::where('appointment_id', $appointment->id)
            ->where('status', AppointmentServiceAddition::STATUS_ACTIVE)
            ->find($additionId);

        if (! $addition) {
            return response()->json(['message' => 'That extra is not on this bill.'], 404);
        }

        $this->checkIn->voidAddition($appointment, $addition);

        $appointment = $appointment->fresh($this->checkIn->relations());

        return response()->json([
            'message' => 'Extra removed from the bill.',
            'appointment' => $this->present($appointment),
            'bill' => $this->checkIn->bill($appointment),
        ]);
    }

    /**
     * The bill as it stands, including anything added mid-appointment.
     */
    public function bill(Request $request, $salonId, $appointmentId)
    {
        if ($denied = $this->denyUnlessSalonStaff($request, $salonId)) {
            return $denied;
        }

        $appointment = Appointment::with($this->checkIn->relations())
            ->where('salon_id', $salonId)
            ->findOrFail($appointmentId);

        return response()->json([
            'appointment' => $this->present($appointment),
            'bill' => $this->checkIn->bill($appointment),
        ]);
    }

    /**
     * Take the balance and finish the job. There is no tab, so these are one
     * action.
     */
    public function collectPayment(Request $request, $salonId, $appointmentId)
    {
        if ($denied = $this->denyUnlessSalonStaff($request, $salonId)) {
            return $denied;
        }

        $validator = Validator::make($request->all(), [
            'payment_mode' => 'required|in:' . implode(',', AppointmentCheckInService::PAYMENT_MODES),
            'note' => 'nullable|string|max:255',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $appointment = Appointment::with($this->checkIn->relations())
            ->where('salon_id', $salonId)
            ->findOrFail($appointmentId);

        if ($appointment->status === 'completed') {
            return response()->json(['message' => 'This appointment is already settled.'], 422);
        }

        if ($appointment->status !== 'in_progress') {
            return response()->json([
                'message' => 'Start the appointment before collecting payment.',
            ], 422);
        }

        $result = $this->checkIn->collectPaymentAndComplete(
            $appointment,
            $request->payment_mode,
            $request->user(),
            $request->input('note')
        );

        return response()->json([
            'message' => 'Payment collected and appointment completed.',
            'appointment' => $this->present($result['appointment']),
            'bill' => $result['bill'],
            'coins_earned' => $result['coins_earned'],
            'new_balance' => $result['new_balance'],
        ]);
    }

    /**
     * Today's bookings that are still waiting to be checked in. Backs the
     * "find them in the list" path when a QR cannot be scanned.
     */
    public function pending(Request $request, $salonId)
    {
        if ($denied = $this->denyUnlessSalonStaff($request, $salonId)) {
            return $denied;
        }

        $date = $request->input('date', Carbon::today()->toDateString());

        $query = Appointment::with($this->checkIn->relations())
            ->where('salon_id', $salonId)
            ->whereDate('appointment_date', $date)
            ->whereIn('status', ['scheduled', 'in_progress'])
            ->orderBy('start_time');

        // A service provider only needs to see their own queue.
        if ($request->user()->role === 'service_provider') {
            $provider = ServiceProvider::where('user_id', $request->user()->id)
                ->where('salon_id', $salonId)
                ->first();

            if ($provider) {
                $query->where(function ($q) use ($provider) {
                    $q->where('appointed_provider_id', $provider->id)
                      ->orWhere('serving_provider_id', $provider->id);
                });
            }
        }

        return response()->json([
            'date' => $date,
            'appointments' => $query->get()->map(fn ($a) => $this->present($a))->values(),
        ]);
    }

    // ------------------------------------------------------------- internals

    private function present(Appointment $appointment): array
    {
        return $this->checkIn->present($appointment);
    }

    private function providerBelongsToSalon(?string $providerId, string $salonId): bool
    {
        if (! $providerId) {
            return true; // "Any staff" — resolved later.
        }

        return ServiceProvider::where('id', $providerId)->where('salon_id', $salonId)->exists();
    }

    /**
     * The salon's owner or one of its active staff. Starting a session and
     * taking money both move real money, so neither may be done by anyone who
     * simply knows a salon id.
     */
    private function denyUnlessSalonStaff(Request $request, string $salonId)
    {
        $user = $request->user();

        if ($user->role === 'superadmin') {
            return null;
        }

        if ($user->role === 'admin'
            && Salon::where('id', $salonId)->where('admin_id', $user->id)->exists()) {
            return null;
        }

        if ($user->role === 'service_provider'
            && ServiceProvider::where('user_id', $user->id)
                ->where('salon_id', $salonId)
                ->where('is_active', true)
                ->exists()) {
            return null;
        }

        return response()->json(['message' => 'You do not work at this salon.'], 403);
    }
}
