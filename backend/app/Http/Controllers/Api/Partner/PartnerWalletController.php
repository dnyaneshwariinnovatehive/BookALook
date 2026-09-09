<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\Salon;
use App\Models\SalonPayout;
use App\Models\SubscriptionPlan;
use App\Models\WalletTransaction;
use App\Services\WalletService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

/**
 * The salon's rewards wallet: what they have, how they earned it, and the two
 * places they are allowed to spend it.
 */
class PartnerWalletController extends Controller
{
    public function __construct(private WalletService $wallet)
    {
    }

    /**
     * Balance, ladder progress, and both histories.
     */
    public function getWallet(Request $request, $salonId)
    {
        if ($denied = $this->denyUnlessOwner($request, $salonId)) {
            return $denied;
        }

        $wallet = $this->wallet->walletFor($salonId);
        $coinValue = $this->wallet->coinValue();

        $transactions = WalletTransaction::with([
                'tier.scheme:id,name',
                'appointment:id,appointment_date,start_time',
                'payout:id,cycle_type,cycle_start_date,cycle_end_date',
                'subscription:id,plan_id,plan_price_snapshot',
            ])
            ->where('salon_id', $salonId)
            ->orderByDesc('created_at')
            ->limit(200)
            ->get();

        return response()->json([
            'success' => true,
            'balance' => (int) $wallet->coin_balance,
            'coin_value_inr' => $coinValue,
            'balance_value_inr' => round($wallet->coin_balance * $coinValue, 2),
            'can_redeem_against_commission' => $this->wallet->isOnCommissionPlan($salonId),
            'progress' => $this->wallet->progress($salonId),
            // Split so the app can show "how I earned" and "how I spent"
            // separately without filtering client-side.
            'earned' => $transactions->where('type', WalletTransaction::TYPE_EARNED)
                ->map(fn ($t) => $this->present($t))->values(),
            // The salon-facing summary: what each reward scheme earned them, and
            // when (grouped by month), instead of one row per appointment.
            'earned_by_scheme' => $this->earnedByScheme(
                $transactions->where('type', WalletTransaction::TYPE_EARNED)
            ),
            'redeemed' => $transactions->where('type', WalletTransaction::TYPE_REDEEMED)
                ->map(fn ($t) => $this->present($t))->values(),
            'transactions' => $transactions->map(fn ($t) => $this->present($t))->values(),
        ]);
    }

    /**
     * What coins would be worth against a given bill, without spending them.
     */
    public function quote(Request $request, $salonId)
    {
        if ($denied = $this->denyUnlessOwner($request, $salonId)) {
            return $denied;
        }

        $validator = Validator::make($request->all(), [
            'against' => 'required_without:plan_id|numeric|min:0',
            'plan_id' => 'required_without:against|exists:subscription_plans,id',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $amount = $request->filled('plan_id')
            ? (float) SubscriptionPlan::findOrFail($request->plan_id)->price
            : (float) $request->against;

        $quote = $this->wallet->quote($salonId, $amount);

        return response()->json([
            'success' => true,
            'bill_amount' => round($amount, 2),
            'coins_usable' => $quote['coins'],
            'discount_value' => $quote['value'],
            'payable_after_coins' => round(max($amount - $quote['value'], 0), 2),
            'coin_value_inr' => $this->wallet->coinValue(),
        ]);
    }

    /**
     * Settle coins against commission owed on a payout. Only open to salons on
     * a Commission Model.
     */
    public function redeemCommission(Request $request, $salonId)
    {
        if ($denied = $this->denyUnlessOwner($request, $salonId)) {
            return $denied;
        }

        $validator = Validator::make($request->all(), [
            'payout_id' => 'required|uuid',
            'coins_to_redeem' => 'required|integer|min:1',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $payout = SalonPayout::where('id', $request->payout_id)
            ->where('salon_id', $salonId)
            ->first();

        if (! $payout) {
            return response()->json(['message' => 'That payout does not belong to this salon.'], 404);
        }

        try {
            $result = $this->wallet->redeemAgainstCommission(
                $salonId,
                $payout,
                (int) $request->coins_to_redeem,
                $request->user()
            );
        } catch (\RuntimeException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], 422);
        }

        // The payout carries the settled amount so the distribution side pays
        // out the right net figure.
        $payout->wallet_redeemed_amount = round(
            (float) $payout->wallet_redeemed_amount + $result['value'],
            2
        );
        $payout->net_amount = round((float) $payout->net_amount + $result['value'], 2);
        $payout->save();

        return response()->json([
            'success' => true,
            'message' => "{$result['coins']} coin(s) settled against commission.",
            'coins_redeemed' => $result['coins'],
            'discount_applied' => $result['value'],
            'new_balance' => $result['new_balance'],
        ]);
    }

    /**
     * How the salon's coins were earned, grouped by reward scheme and then by
     * the month each batch of coins landed. This is what the partner reads on
     * the wallet screen instead of a long line of per-appointment +1/+2 rows.
     *
     * @param  \Illuminate\Support\Collection<int, \App\Models\WalletTransaction>  $earned
     * @return array<int, array{
     *   scheme_id: ?string,
     *   scheme_name: ?string,
     *   total_coins: int,
     *   total_value_inr: float,
     *   months: array<int, array{month: ?string, month_label: ?string, coins: int, value_inr: float}>
     * }>
     */
    private function earnedByScheme($earned): array
    {
        $byScheme = [];

        foreach ($earned as $transaction) {
            $scheme = $transaction->tier?->scheme;
            $key = $scheme?->id ?? 'other';

            if (! isset($byScheme[$key])) {
                $byScheme[$key] = [
                    'scheme_id' => $scheme?->id,
                    'scheme_name' => $scheme?->name ?? 'Other',
                    'total_coins' => 0,
                    'total_value_inr' => 0.0,
                    'months' => [],
                ];
            }

            $coins = (int) $transaction->coins;
            $value = $transaction->coin_value_snapshot !== null
                ? round($coins * (float) $transaction->coin_value_snapshot, 2)
                : 0.0;

            $byScheme[$key]['total_coins'] += $coins;
            $byScheme[$key]['total_value_inr'] = round(
                (float) $byScheme[$key]['total_value_inr'] + $value,
                2
            );

            $month = $transaction->created_at?->format('Y-m');
            $monthLabel = $transaction->created_at?->format('M Y');
            $monthKey = $month ?? 'unknown';

            if (! isset($byScheme[$key]['months'][$monthKey])) {
                $byScheme[$key]['months'][$monthKey] = [
                    'month' => $month,
                    'month_label' => $monthLabel,
                    'coins' => 0,
                    'value_inr' => 0.0,
                ];
            }

            $byScheme[$key]['months'][$monthKey]['coins'] += $coins;
            $byScheme[$key]['months'][$monthKey]['value_inr'] = round(
                (float) $byScheme[$key]['months'][$monthKey]['value_inr'] + $value,
                2
            );
        }

        $result = array_values($byScheme);

        // Newest month first within each scheme; highest-earning scheme first.
        foreach ($result as &$group) {
            $group['months'] = array_values($group['months']);
            usort(
                $group['months'],
                fn ($a, $b) => strcmp((string) ($b['month'] ?? ''), (string) ($a['month'] ?? ''))
            );
        }
        unset($group);

        uasort($result, fn ($a, $b) => $b['total_coins'] <=> $a['total_coins']);

        return array_values($result);
    }

    private function present(WalletTransaction $transaction): array
    {
        return [
            'id' => $transaction->id,
            'type' => $transaction->type,
            'coins' => (int) $transaction->coins,
            'balance_after' => (int) $transaction->balance_after,
            'coin_value_inr' => $transaction->coin_value_snapshot !== null
                ? (float) $transaction->coin_value_snapshot
                : null,
            'value_inr' => $transaction->coin_value_snapshot !== null
                ? round(abs((int) $transaction->coins) * (float) $transaction->coin_value_snapshot, 2)
                : null,
            'note' => $transaction->note,
            'scheme_name' => $transaction->tier->scheme->name ?? null,
            'tier_label' => $transaction->tier
                ? ($transaction->tier->appointments_to === null
                    ? "From {$transaction->tier->appointments_from} onwards"
                    : "{$transaction->tier->appointments_from}–{$transaction->tier->appointments_to}")
                : null,
            'appointment_id' => $transaction->related_appointment_id,
            'payout_id' => $transaction->related_payout_id,
            'subscription_id' => $transaction->related_subscription_id,
            'created_at' => $transaction->created_at,
        ];
    }

    private function denyUnlessOwner(Request $request, string $salonId)
    {
        $user = $request->user();

        if ($user->role === 'superadmin') {
            return null;
        }

        if ($user->role === 'admin'
            && Salon::where('id', $salonId)->where('admin_id', $user->id)->exists()) {
            return null;
        }

        return response()->json(['message' => 'Only the salon owner can use its wallet.'], 403);
    }
}
