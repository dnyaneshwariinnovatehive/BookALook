<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use App\Models\AppointmentServiceAddition;
use App\Models\Service;
use App\Models\ServiceProvider;
use App\Models\PlatformPolicySetting;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

class SuperAdminAppointmentController extends Controller
{
    /**
     * Get global appointments list with filters.
     */
    public function index(Request $request)
    {
        $query = Appointment::with([
            'salon:id,name,address,phone,email,status',
            'customer:id,name,phone,email',
            'appointedProvider:id,user_id,salon_id',
            'servingProvider:id,user_id,salon_id',
            'appointedProvider.user:id,name,phone',
            'servingProvider.user:id,name,phone',
            // The template carries the service name and standard duration.
            'services.service.template',
            'services.servingProvider.user:id,name',
            'serviceAdditions.service.template',
            'serviceAdditions.provider.user:id,name',
            'serviceAdditions.addedBy:id,name,role',
            'cancelledByUser:id,name,role',
            'salonClosure:id,closed_date,reason',
        ]);

        // Filter by Date
        if ($request->has('date')) {
            $query->whereDate('appointment_date', $request->date);
        } elseif ($request->has('start_date') && $request->has('end_date')) {
            $query->whereBetween('appointment_date', [$request->start_date, $request->end_date]);
        }

        // Filter by Staff/Provider
        if ($request->has('provider_id')) {
            $query->where(function ($q) use ($request) {
                $q->where('appointed_provider_id', $request->provider_id)
                  ->orWhere('serving_provider_id', $request->provider_id);
            });
        }

        // Filter by Service
        if ($request->has('service_id')) {
            $query->whereHas('services', function ($q) use ($request) {
                $q->where('service_id', $request->service_id);
            })->orWhereHas('serviceAdditions', function ($q) use ($request) {
                $q->where('service_id', $request->service_id);
            });
        }

        // Filter by Salon
        if ($request->has('salon_id') && $request->salon_id != '') {
            $query->where('salon_id', $request->salon_id);
        }

        // Filter by Search (Customer Name, Phone, Email, or Appointment ID)
        if ($request->has('search') && $request->search != '') {
            $search = $request->search;
            $query->where(function ($q) use ($search) {
                $q->whereHas('customer', function ($cq) use ($search) {
                    $cq->where('name', 'like', "%{$search}%")
                       ->orWhere('phone', 'like', "%{$search}%")
                       ->orWhere('email', 'like', "%{$search}%");
                })->orWhere('id', 'like', "%{$search}%")
                  ->orWhere('walk_in_customer_name', 'like', "%{$search}%")
                  ->orWhere('walk_in_customer_phone', 'like', "%{$search}%");
            });
        }

        // Filter by Status
        if ($request->has('status')) {
            $query->where('status', $request->status);
        }

        // Filter by Booking Source
        if ($request->has('booking_source')) {
            $query->where('booking_source', $request->booking_source);
        }

        $appointments = $query->orderBy('appointment_date', 'desc')
                              ->orderBy('start_time', 'desc')
                              ->paginate($request->get('per_page', 20));

        return response()->json($appointments);
    }

    /**
     * Scan Customer QR and start session.
     */
    public function verifyQrAndStartSession(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'qr_token' => 'required|string',
            'serving_provider_id' => 'required|exists:service_providers,id'
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $qrTokenHash = hash('sha256', $request->qr_token);

        $appointment = Appointment::where('qr_token_hash', $qrTokenHash)->first();

        if (!$appointment) {
            return response()->json(['message' => 'Invalid QR Code.'], 404);
        }

        if ($appointment->status !== 'scheduled') {
            return response()->json(['message' => 'Appointment is not in a scheduled state.'], 400);
        }

        if ($appointment->qr_expires_at && now()->greaterThan($appointment->qr_expires_at)) {
            return response()->json(['message' => 'QR Code has expired.'], 400);
        }

        $earlyAllowance = (int) PlatformPolicySetting::value('appointment_start_early_minutes');
        $appointmentStart = Carbon::parse(
            Carbon::parse($appointment->appointment_date)->format('Y-m-d') . ' ' . $appointment->start_time
        );

        if (now()->addMinutes($earlyAllowance)->lessThan($appointmentStart)) {
            return response()->json(['message' => 'It is too early to start this appointment.'], 400);
        }

        $appointment->status = 'in_progress';
        $appointment->serving_provider_id = $request->serving_provider_id;
        $appointment->qr_verified_at = now();
        $appointment->qr_verified_by = $request->user()->id; // Superadmin user
        $appointment->started_at = now();
        $appointment->save();

        return response()->json([
            'message' => 'Session started successfully.',
            'appointment' => $appointment->load('servingProvider.user')
        ]);
    }

    /**
     * Add service mid-appointment.
     */
    public function addServiceMidAppointment(Request $request, $id)
    {
        $validator = Validator::make($request->all(), [
            'service_id' => 'required|exists:services,id',
            'provider_id' => 'required|exists:service_providers,id',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $appointment = Appointment::findOrFail($id);

        if ($appointment->status !== 'in_progress') {
            return response()->json(['message' => 'Can only add services to in-progress appointments.'], 400);
        }

        $service = Service::findOrFail($request->service_id);

        DB::beginTransaction();
        try {
            // Add service addition record
            $addition = new AppointmentServiceAddition([
                'appointment_id' => $appointment->id,
                'service_id' => $service->id,
                'provider_id' => $request->provider_id,
                'added_by' => $request->user()->id,
                'price_at_addition' => $service->price,
                'duration_minutes_at_addition' => $service->duration_minutes,
                'status' => 'active'
            ]);
            $addition->save();

            // Recalculate total billed amount
            // existing total_amount + sum of additions
            $baseAmount = $appointment->services()->sum('price_at_booking');
            $additionsAmount = $appointment->serviceAdditions()->live()->sum('price_at_addition');
            
            $appointment->total_amount = $baseAmount + $additionsAmount;
            
            // Advance amount remains the same, balance changes
            $appointment->balance_amount = $appointment->total_amount - $appointment->advance_amount;
            
            $appointment->save();

            DB::commit();

            return response()->json([
                'message' => 'Service added successfully.',
                'appointment' => $appointment->load('services', 'serviceAdditions.service', 'serviceAdditions.provider.user')
            ]);
        } catch (\Exception $e) {
            DB::rollBack();
            return response()->json(['message' => 'Failed to add service.', 'error' => $e->getMessage()], 500);
        }
    }
}
