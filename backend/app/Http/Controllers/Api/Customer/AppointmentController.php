<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use App\Models\AppointmentService;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\PlatformPolicySetting;
use App\Models\ServiceProvider;
use App\Models\Salon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;
use Carbon\Carbon;

class AppointmentController extends Controller
{
    /**
     * Get available slots for a given date and duration (calculated from cart).
     * This is a simplified availability engine.
     */
    public function getAvailableSlots(Request $request, $salon_id)
    {
        $validator = Validator::make($request->all(), [
            'date' => 'required|date|after_or_equal:today',
            'provider_id' => 'nullable|exists:service_providers,id'
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $date = $request->date;
        $providerId = $request->provider_id;

        // In a real implementation, we would:
        // 1. Fetch Salon Working Hours for the day of the week
        // 2. Fetch Provider Working Hours and Leaves
        // 3. Fetch existing appointments for the day
        // 4. Calculate total duration required from the user's Cart
        // 5. Generate 30-min consecutive blocks that fit the duration

        // For this demo, we'll return mock 30-min slots between 10:00 and 18:00
        $slots = [];
        $startTime = Carbon::parse($date . ' 10:00:00');
        $endTime = Carbon::parse($date . ' 18:00:00');

        while ($startTime->lessThan($endTime)) {
            $slots[] = [
                'time' => $startTime->format('H:i'),
                'available' => true // Assume all available for demo
            ];
            $startTime->addMinutes(30);
        }

        return response()->json([
            'date' => $date,
            'slots' => $slots
        ]);
    }

    /**
     * Book an appointment from the cart.
     */
    public function book(Request $request, $salon_id)
    {
        $validator = Validator::make($request->all(), [
            'date' => 'required|date|after_or_equal:today',
            'time' => 'required|date_format:H:i',
            'provider_id' => 'nullable|exists:service_providers,id' // null means 'Any Available'
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $user = $request->user();
        
        $cart = Cart::with('items.service', 'items.combo')
            ->where('customer_id', $user->id)
            ->where('salon_id', $salon_id)
            ->where('status', 'active')
            ->first();

        if (!$cart || $cart->items->isEmpty()) {
            return response()->json(['message' => 'Cart is empty.'], 400);
        }

        DB::beginTransaction();
        try {
            // Resolve provider (If 'Any', pick the first available provider for the salon)
            $appointedProviderId = $request->provider_id;
            if (!$appointedProviderId) {
                $firstProvider = ServiceProvider::where('salon_id', $salon_id)->first();
                if (!$firstProvider) {
                    throw new \Exception('No service providers available in this salon.');
                }
                $appointedProviderId = $firstProvider->id;
            }

            // Calculate totals
            $totalAmount = 0;
            $totalDuration = 0;
            foreach ($cart->items as $item) {
                if ($item->service) {
                    $totalAmount += $item->service->price * $item->quantity;
                    $totalDuration += $item->service->duration_minutes * $item->quantity;
                }
            }

            // Simple flat advance for demo
            $advanceAmount = 100.00;
            if ($totalAmount < $advanceAmount) {
                $advanceAmount = $totalAmount;
            }

            $endTime = Carbon::parse($request->date . ' ' . $request->time)->addMinutes($totalDuration)->format('H:i:s');

            $appointment = new Appointment([
                'salon_id' => $salon_id,
                'customer_id' => $user->id,
                'appointed_provider_id' => $appointedProviderId,
                'booking_source' => 'online',
                'appointment_date' => $request->date,
                'start_time' => $request->time . ':00',
                'end_time' => $endTime,
                'status' => 'scheduled',
                'payment_option' => 'advance_only',
                'total_amount' => $totalAmount,
                'advance_amount' => $advanceAmount,
                'balance_amount' => $totalAmount - $advanceAmount,
            ]);
            $appointment->save();

            // Create Appointment Services
            foreach ($cart->items as $item) {
                if ($item->service) {
                    for ($i = 0; $i < $item->quantity; $i++) {
                        AppointmentService::create([
                            'appointment_id' => $appointment->id,
                            'service_id' => $item->service_id,
                            'price_at_booking' => $item->service->price,
                            'original_service_price' => $item->service->price,
                            'duration_minutes_at_booking' => $item->service->duration_minutes,
                            'line_status' => 'booked'
                        ]);
                    }
                }
            }

            // Clear the cart
            $cart->items()->delete();
            $cart->status = 'converted';
            $cart->save();

            DB::commit();

            return response()->json([
                'message' => 'Appointment booked successfully.',
                'appointment' => $appointment->load('services.service', 'appointedProvider.user')
            ]);
        } catch (\Exception $e) {
            DB::rollBack();
            return response()->json(['message' => 'Failed to book appointment.', 'error' => $e->getMessage()], 500);
        }
    }

    /**
     * Get Customer's upcoming and past appointments.
     */
    public function index(Request $request)
    {
        $appointments = Appointment::with(['salon:id,name', 'services.service', 'appointedProvider.user:id,name'])
            ->where('customer_id', $request->user()->id)
            ->orderBy('appointment_date', 'desc')
            ->orderBy('start_time', 'desc')
            ->get();

        $upcoming = [];
        $past = [];
        $now = now();

        foreach ($appointments as $apt) {
            $aptDateTime = Carbon::parse($apt->appointment_date . ' ' . $apt->start_time);
            if ($apt->status === 'scheduled' && $aptDateTime->isFuture()) {
                $upcoming[] = $apt;
            } else {
                $past[] = $apt;
            }
        }

        return response()->json([
            'upcoming' => $upcoming,
            'past' => $past
        ]);
    }

    /**
     * Cancel an appointment.
     */
    public function cancel(Request $request, $id)
    {
        $appointment = Appointment::where('customer_id', $request->user()->id)->findOrFail($id);

        if ($appointment->status !== 'scheduled') {
            return response()->json(['message' => 'Only scheduled appointments can be cancelled.'], 400);
        }

        // Check cancellation cutoff
        $policy = PlatformPolicySetting::first();
        $cutoffMinutes = $policy ? $policy->cancellation_cutoff_minutes : 90;
        
        $aptDateTime = Carbon::parse($appointment->appointment_date . ' ' . $appointment->start_time);
        if (now()->addMinutes($cutoffMinutes)->greaterThan($aptDateTime)) {
            return response()->json(['message' => "Appointments cannot be cancelled within {$cutoffMinutes} minutes of start time."], 400);
        }

        $appointment->status = 'cancelled';
        $appointment->cancelled_by = 'customer';
        $appointment->cancelled_by_user_id = $request->user()->id;
        $appointment->cancelled_at = now();
        $appointment->save();

        return response()->json(['message' => 'Appointment cancelled successfully.', 'appointment' => $appointment]);
    }

    /**
     * Generate QR code for same-day appointment.
     */
    public function generateQr(Request $request, $id)
    {
        $appointment = Appointment::where('customer_id', $request->user()->id)->findOrFail($id);

        if ($appointment->status !== 'scheduled') {
            return response()->json(['message' => 'QR can only be generated for scheduled appointments.'], 400);
        }

        // Ensure it's for today
        if (Carbon::parse($appointment->appointment_date)->format('Y-m-d') !== now()->format('Y-m-d')) {
            return response()->json(['message' => 'QR can only be generated on the day of the appointment.'], 400);
        }

        $policy = PlatformPolicySetting::first();
        $validityMins = $policy ? $policy->qr_validity_minutes : 60;

        // Generate a random token
        $rawToken = Str::random(32);
        
        $appointment->qr_token_hash = hash('sha256', $rawToken);
        $appointment->qr_generated_at = now();
        $appointment->qr_expires_at = now()->addMinutes($validityMins);
        $appointment->save();

        return response()->json([
            'message' => 'QR Code generated successfully.',
            'qr_token' => $rawToken, // The frontend will encode this string into a QR graphic
            'expires_at' => $appointment->qr_expires_at
        ]);
    }
}
