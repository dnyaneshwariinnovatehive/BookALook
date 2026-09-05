<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\SalonWallet;

class PartnerWalletController extends Controller
{
    public function getWallet(Request $request)
    {
        $user = $request->user();
        
        $salon = \App\Models\Salon::where('admin_id', $user->id)->first();
        if (!$salon) {
            return response()->json(['success' => false, 'message' => 'Salon not found'], 404);
        }
        $salonId = $salon->id; 

        $wallet = SalonWallet::firstOrCreate(
            ['salon_id' => $salonId],
            ['coin_balance' => 0]
        );

        $transactions = $wallet->transactions()->orderBy('created_at', 'desc')->get();

        return response()->json([
            'success' => true,
            'balance' => $wallet->coin_balance,
            'transactions' => $transactions
        ]);
    }

    public function redeemCommission(Request $request)
    {
        $request->validate([
            'payout_id' => 'required|uuid',
            'coins_to_redeem' => 'required|integer|min:1'
        ]);

        $user = $request->user();
        $salon = \App\Models\Salon::where('admin_id', $user->id)->first();
        if (!$salon) {
            return response()->json(['success' => false, 'message' => 'Salon not found'], 404);
        }
        $salonId = $salon->id;

        $wallet = SalonWallet::where('salon_id', $salonId)->first();
        if (!$wallet || $wallet->coin_balance < $request->coins_to_redeem) {
            return response()->json(['success' => false, 'message' => 'Insufficient coin balance.'], 400);
        }

        $payout = \App\Models\SalonPayout::where('id', $request->payout_id)
            ->where('salon_id', $salonId)
            ->firstOrFail();

        // Check if platform policy defines a coin value, or assume 1 coin = 1 unit for now
        $coinValue = 1.00; // Mock: 1 coin = 1 INR discount
        $discountAmount = $request->coins_to_redeem * $coinValue;

        // Deduct from wallet
        $wallet->coin_balance -= $request->coins_to_redeem;
        $wallet->save();

        // Record transaction
        \App\Models\WalletTransaction::create([
            'salon_id' => $salonId,
            'type' => 'redeemed',
            'coins' => -($request->coins_to_redeem),
            'balance_after' => $wallet->coin_balance,
            'related_payout_id' => $payout->id,
            'note' => "Redeemed against commission payout"
        ]);

        // Adjust payout (assuming there is a wallet_redeemed_amount or deduction column)
        // From doc: wallet_redeemed_amount
        $payout->wallet_redeemed_amount = ($payout->wallet_redeemed_amount ?? 0) + $discountAmount;
        $payout->save();

        return response()->json([
            'success' => true,
            'message' => 'Coins redeemed successfully against commission payout.',
            'new_balance' => $wallet->coin_balance,
            'discount_applied' => $discountAmount
        ]);
    }
}
