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
        $provider = \App\Models\ServiceProvider::where('user_id', $request->user()->id)->first();
        if (!$provider) {
            return response()->json(['message' => 'You are not a registered service provider.'], 403);
        }

        $query = Appointment::with(['customer', 'services.service', 'serviceAdditions.service'])
            ->where('salon_id', $salon_id)
            ->where(function($q) use ($provider) {
                $q->where('appointed_provider_id', $provider->id)
                  ->orWhere('serving_provider_id', $provider->id);
            });

        if ($request->has('date')) {
            $query->whereDate('appointment_date', $request->date);
        }

        $appointments = $query->orderBy('start_time', 'asc')->get();
        return response()->json(['appointments' => $appointments]);
    }

    public function walkIn(Request $request, $salon_id)
    {
        $request->validate([
            'customer_name' => 'required|string',
            'customer_phone' => 'required|string',
            'services' => 'required|array',
            'services.*' => 'exists:services,id'
        ]);

        $provider = \App\Models\ServiceProvider::where('user_id', $request->user()->id)->first();
        if (!$provider) return response()->json(['message' => 'Not a service provider'], 403);

        $services = \App\Models\Service::whereIn('id', $request->services)->get();
        $totalAmount = $services->sum('price');
        $totalDuration = $services->sum('duration_minutes');

        \Illuminate\Support\Facades\DB::beginTransaction();
        try {
            $appointment = new Appointment([
                'salon_id' => $salon_id,
                'appointed_provider_id' => $provider->id,
                'serving_provider_id' => $provider->id,
                'booking_source' => 'walk_in',
                'walk_in_customer_name' => $request->customer_name,
                'walk_in_customer_phone' => $request->customer_phone,
                'appointment_date' => now()->format('Y-m-d'),
                'start_time' => now()->format('H:i:s'),
                'end_time' => now()->addMinutes($totalDuration)->format('H:i:s'),
                'status' => 'in_progress',
                'payment_option' => 'full_at_venue',
                'total_amount' => $totalAmount,
                'advance_amount' => 0,
                'balance_amount' => $totalAmount,
                'started_at' => now(),
            ]);
            $appointment->save();

            foreach ($services as $service) {
                \App\Models\AppointmentService::create([
                    'appointment_id' => $appointment->id,
                    'service_id' => $service->id,
                    'serving_provider_id' => $provider->id,
                    'price_at_booking' => $service->price,
                    'original_service_price' => $service->price,
                    'duration_minutes_at_booking' => $service->duration_minutes,
                    'line_status' => 'in_progress'
                ]);
            }

            \Illuminate\Support\Facades\DB::commit();
            return response()->json(['message' => 'Walk-in started', 'appointment' => $appointment]);
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

        $service = \App\Models\Service::findOrFail($request->service_id);

        \Illuminate\Support\Facades\DB::beginTransaction();
        try {
            \App\Models\AppointmentServiceAddition::create([
                'appointment_id' => $appointment->id,
                'service_id' => $service->id,
                'provider_id' => $request->provider_id,
                'added_by' => $request->user()->id,
                'price_at_addition' => $service->price,
                'duration_minutes_at_addition' => $service->duration_minutes,
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
        $appointment->status = 'no_show';
        $appointment->no_show_at = now();
        $appointment->save();
        return response()->json(['message' => 'Marked as no show.']);
    }

    public function complete(Request $request, $id)
    {
        $appointment = Appointment::findOrFail($id);
        
        // Mark appointment as completed
        $appointment->status = 'completed';
        $appointment->completed_at = now();
        $appointment->final_billed_amount = $appointment->total_amount;
        $appointment->save();

        // Increment the wallet count
        $wallet = SalonWallet::firstOrCreate(
            ['salon_id' => $appointment->salon_id],
            ['coin_balance' => 0, 'completed_online_appointments_count' => 0]
        );

        $wallet->completed_online_appointments_count += 1;
        
        // Evaluate ladder tiers
        $schemes = WalletScheme::where('is_active', true)->with('tiers')->get();
        $coinsEarned = 0;
        
        foreach ($schemes as $scheme) {
            foreach ($scheme->tiers as $tier) {
                // If this exact appointment hits the milestone
                // Example: If tier requires 10 appointments, and we just hit 10
                if ($tier->appointments_required == $wallet->completed_online_appointments_count) {
                    $coinsEarned += $tier->coins_awarded;
                    
                    WalletTransaction::create([
                        'salon_id' => $appointment->salon_id,
                        'type' => 'earned',
                        'coins' => $tier->coins_awarded,
                        'balance_after' => $wallet->coin_balance + $coinsEarned,
                        'related_scheme_tier_id' => $tier->id,
                        'related_appointment_id' => $appointment->id,
                        'note' => "Milestone reached for tier {$tier->tier_order} in scheme {$scheme->name}"
                    ]);
                }
            }
        }
        
        if ($coinsEarned > 0) {
            $wallet->coin_balance += $coinsEarned;
        }
        
        $wallet->save();

        return response()->json([
            'success' => true,
            'message' => 'Appointment completed successfully.',
            'coins_earned_this_time' => $coinsEarned,
            'new_balance' => $wallet->coin_balance
        ]);
    }
}
