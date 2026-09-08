<?php

namespace App\Services;

use App\Models\Appointment;
use App\Models\PlatformPolicySetting;
use App\Models\SalonPayout;
use App\Models\SalonSubscription;
use App\Models\SalonWallet;
use App\Models\User;
use App\Models\WalletScheme;
use App\Models\WalletSchemeTier;
use App\Models\WalletTransaction;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * The salon rewards wallet.
 *
 * Salons earn coins for completed online appointments against a ladder
 * SuperAdmin publishes, and can spend them in exactly two places: their next
 * subscription purchase, or the commission they owe on a Commission Model.
 * Coins are never cash and are never paid out — that is the separate payout
 * system's job.
 *
 * Every movement is written to wallet_transactions with the balance it produced
 * and the coin rate at the time, so history stays truthful even after SuperAdmin
 * changes the rate.
 */
class WalletService
{
    /** Platform setting holding what one coin is worth, in rupees. */
    public const COIN_VALUE_KEY = 'coin_value_inr';

    /** Only these bookings count towards the ladder. */
    public const REWARDABLE_SOURCE = 'online';

    /** What one coin is worth in rupees right now. */
    public function coinValue(): float
    {
        return (float) PlatformPolicySetting::value(self::COIN_VALUE_KEY);
    }

    public function walletFor(string $salonId): SalonWallet
    {
        return SalonWallet::firstOrCreate(
            ['salon_id' => $salonId],
            ['coin_balance' => 0, 'completed_online_appointments_count' => 0]
        );
    }

    /**
     * The scheme in force on a date: active, and inside its window if it has
     * one. When several qualify the newest wins, so publishing a new ladder
     * supersedes the old one without having to switch the old one off.
     */
    public function schemeInForceOn(?Carbon $on = null): ?WalletScheme
    {
        $date = ($on ?? now())->toDateString();

        return WalletScheme::with('tiers')
            ->active()
            ->where(fn ($q) => $q->whereNull('starts_on')->orWhereDate('starts_on', '<=', $date))
            ->where(fn ($q) => $q->whereNull('ends_on')->orWhereDate('ends_on', '>=', $date))
            ->orderByDesc('created_at')
            ->first();
    }

    /**
     * Award coins for a completed appointment.
     *
     * Only online bookings count — a walk-in the salon booked itself is not a
     * booking the platform brought them. Awarding is idempotent per appointment
     * so a retried completion cannot mint coins twice.
     *
     * @return array{coins_earned: int, new_balance: int, tier: ?WalletSchemeTier}
     */
    public function awardForCompletedAppointment(Appointment $appointment): array
    {
        $wallet = $this->walletFor($appointment->salon_id);

        if ($appointment->booking_source !== self::REWARDABLE_SOURCE) {
            return ['coins_earned' => 0, 'new_balance' => (int) $wallet->coin_balance, 'tier' => null];
        }

        $alreadyAwarded = WalletTransaction::where('related_appointment_id', $appointment->id)
            ->where('type', WalletTransaction::TYPE_EARNED)
            ->exists();

        if ($alreadyAwarded) {
            return ['coins_earned' => 0, 'new_balance' => (int) $wallet->coin_balance, 'tier' => null];
        }

        return DB::transaction(function () use ($appointment) {
            // Locked so two tills completing at once cannot both claim the same
            // position on the ladder.
            $wallet = SalonWallet::where('salon_id', $appointment->salon_id)
                ->lockForUpdate()
                ->first() ?? $this->walletFor($appointment->salon_id);

            $position = (int) $wallet->completed_online_appointments_count + 1;
            $wallet->completed_online_appointments_count = $position;

            $scheme = $this->schemeInForceOn();
            $tier = $scheme ? $this->tierFor($scheme, $position) : null;
            $coins = $tier ? $this->coinsForPosition($scheme, $tier, $position) : 0;

            if ($coins > 0) {
                $wallet->coin_balance = (int) $wallet->coin_balance + $coins;
            }

            $wallet->save();

            if ($coins > 0) {
                WalletTransaction::create([
                    'salon_id' => $appointment->salon_id,
                    'type' => WalletTransaction::TYPE_EARNED,
                    'coins' => $coins,
                    'balance_after' => $wallet->coin_balance,
                    'coin_value_snapshot' => $this->coinValue(),
                    'related_scheme_tier_id' => $tier->id,
                    'related_appointment_id' => $appointment->id,
                    'note' => sprintf(
                        '%s · appointment #%d%s',
                        $scheme->name,
                        $position,
                        $scheme->award_mode === WalletScheme::MODE_ON_COMPLETION
                            ? ' completed the band'
                            : ''
                    ),
                ]);
            }

            return [
                'coins_earned' => $coins,
                'new_balance' => (int) $wallet->coin_balance,
                'tier' => $tier,
            ];
        });
    }

    /**
     * Spend coins against the next subscription purchase.
     *
     * Returns what the coins are worth so the caller can discount the plan.
     * The caller is responsible for calling this inside the same transaction
     * that creates the subscription — coins must not leave the wallet if the
     * purchase then fails.
     *
     * @return array{coins: int, value: float, new_balance: int}
     */
    public function redeemForSubscription(
        string $salonId,
        int $coins,
        float $cappedAtRupees,
        User $actor,
        ?SalonSubscription $subscription = null,
        ?string $note = null
    ): array {
        return $this->redeem(
            $salonId,
            $coins,
            $cappedAtRupees,
            $actor,
            $note ?? 'Applied to a subscription purchase',
            ['related_subscription_id' => $subscription?->id]
        );
    }

    /**
     * Settle coins against commission owed. Only open to salons on a
     * Commission Model — there is no commission to offset otherwise.
     *
     * @return array{coins: int, value: float, new_balance: int}
     */
    public function redeemAgainstCommission(
        string $salonId,
        SalonPayout $payout,
        int $coins,
        User $actor
    ): array {
        if (! $this->isOnCommissionPlan($salonId)) {
            throw new \RuntimeException(
                'Coins can only be settled against commission on a Commission Model.'
            );
        }

        $outstanding = round(
            (float) $payout->commission_deducted - (float) $payout->wallet_redeemed_amount,
            2
        );

        if ($outstanding <= 0) {
            throw new \RuntimeException('There is no commission left to settle on this payout.');
        }

        return $this->redeem(
            $salonId,
            $coins,
            $outstanding,
            $actor,
            'Settled against commission',
            ['related_payout_id' => $payout->id]
        );
    }

    /**
     * The salon's own flag is the answer, not its subscription row — that row
     * is replaced whenever the arrangement is renewed.
     */
    public function isOnCommissionPlan(string $salonId): bool
    {
        return \App\Models\Salon::where('id', $salonId)
            ->where('commission_opt_in', true)
            ->exists();
    }

    /**
     * How many coins are worth spending against [$rupees], and what they cover.
     * Never lets a salon burn more coins than the bill is worth.
     *
     * @return array{coins: int, value: float}
     */
    public function quote(string $salonId, float $rupees): array
    {
        $coinValue = $this->coinValue();
        $balance = (int) $this->walletFor($salonId)->coin_balance;

        if ($coinValue <= 0 || $balance <= 0 || $rupees <= 0) {
            return ['coins' => 0, 'value' => 0.0];
        }

        // Only whole coins, and never more than the bill.
        $coins = min($balance, (int) floor($rupees / $coinValue));

        return ['coins' => $coins, 'value' => round($coins * $coinValue, 2)];
    }

    /**
     * The ladder as it stands for this salon: which rung they are on, how far
     * to the next one, and what it is worth.
     */
    public function progress(string $salonId): array
    {
        $wallet = $this->walletFor($salonId);
        $scheme = $this->schemeInForceOn();
        $completed = (int) $wallet->completed_online_appointments_count;

        if (! $scheme) {
            return [
                'scheme' => null,
                'completed_online_appointments' => $completed,
                'current_tier' => null,
                'next_tier' => null,
                'appointments_to_next_tier' => null,
            ];
        }

        $current = $this->tierFor($scheme, $completed > 0 ? $completed : 1);
        $next = $scheme->tiers->firstWhere(fn ($tier) => $tier->appointments_from > $completed);

        return [
            'scheme' => [
                'id' => $scheme->id,
                'name' => $scheme->name,
                'description' => $scheme->description,
                'award_mode' => $scheme->award_mode,
            ],
            'completed_online_appointments' => $completed,
            'current_tier' => $current ? $this->presentTier($current) : null,
            'next_tier' => $next ? $this->presentTier($next) : null,
            'appointments_to_next_tier' => $next ? $next->appointments_from - $completed : null,
        ];
    }

    // ------------------------------------------------------------- internals

    /**
     * Move coins out of the wallet and record why.
     *
     * @param  array<string, ?string>  $links
     * @return array{coins: int, value: float, new_balance: int}
     */
    private function redeem(
        string $salonId,
        int $coins,
        float $cappedAtRupees,
        User $actor,
        string $note,
        array $links
    ): array {
        if ($coins < 1) {
            throw new \RuntimeException('Redeem at least one coin.');
        }

        $coinValue = $this->coinValue();

        if ($coinValue <= 0) {
            throw new \RuntimeException('Coins have no value set yet. Ask SuperAdmin to set the coin rate.');
        }

        return DB::transaction(function () use (
            $salonId, $coins, $cappedAtRupees, $actor, $note, $links, $coinValue
        ) {
            $wallet = SalonWallet::where('salon_id', $salonId)->lockForUpdate()->first()
                ?? $this->walletFor($salonId);

            if ((int) $wallet->coin_balance < $coins) {
                throw new \RuntimeException(
                    "Not enough coins. The balance is {$wallet->coin_balance}."
                );
            }

            // Spending more than the bill is worth would quietly destroy coins.
            $maxUseful = (int) floor($cappedAtRupees / $coinValue);

            if ($coins > $maxUseful) {
                throw new \RuntimeException(
                    "Only {$maxUseful} coin(s) can be used here — the rest would be wasted."
                );
            }

            $wallet->coin_balance = (int) $wallet->coin_balance - $coins;
            $wallet->save();

            WalletTransaction::create(array_merge([
                'salon_id' => $salonId,
                'type' => WalletTransaction::TYPE_REDEEMED,
                // Negative, so summing the column gives the balance.
                'coins' => -$coins,
                'balance_after' => $wallet->coin_balance,
                'coin_value_snapshot' => $coinValue,
                'created_by' => $actor->id,
                'note' => $note,
            ], $links));

            return [
                'coins' => $coins,
                'value' => round($coins * $coinValue, 2),
                'new_balance' => (int) $wallet->coin_balance,
            ];
        });
    }

    private function tierFor(WalletScheme $scheme, int $position): ?WalletSchemeTier
    {
        return $scheme->tiers->first(fn (WalletSchemeTier $tier) => $tier->covers($position));
    }

    /**
     * What this position on the ladder pays. On a per-appointment scheme every
     * position in the band pays; on a completion scheme only the band's last
     * appointment does, and an open-ended band never completes.
     */
    private function coinsForPosition(WalletScheme $scheme, WalletSchemeTier $tier, int $position): int
    {
        if ($scheme->award_mode === WalletScheme::MODE_ON_COMPLETION) {
            return $tier->appointments_to !== null && $position === $tier->appointments_to
                ? (int) $tier->coins_awarded
                : 0;
        }

        return (int) $tier->coins_awarded;
    }

    private function presentTier(WalletSchemeTier $tier): array
    {
        return [
            'id' => $tier->id,
            'tier_order' => $tier->tier_order,
            'appointments_from' => $tier->appointments_from,
            'appointments_to' => $tier->appointments_to,
            'coins_awarded' => $tier->coins_awarded,
        ];
    }
}
