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
    public function complete(Request $request, $id)
    {
        $appointment = Appointment::findOrFail($id);
        
        // Mark appointment as completed
        $appointment->status = 'completed';
        $appointment->completed_at = now();
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
