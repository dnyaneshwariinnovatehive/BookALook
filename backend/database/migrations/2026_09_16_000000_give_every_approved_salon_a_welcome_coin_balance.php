<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Free coins for every approved salon.
 *
 * A salon is approved and immediately asked to pay for a plan, which is the
 * worst possible moment to meet a price for the first time. The welcome bonus
 * puts money against that first purchase before the owner has served anybody,
 * so the ask is "top this up" rather than "start paying".
 *
 * Two things happen here. The amount becomes a real row in
 * platform_policy_settings so SuperAdmin can change it from the policy page —
 * the model default only covers the case where nobody has ever set it. And
 * every salon already trading is given the bonus retroactively, because a
 * benefit that only new salons get is not "free coins for everyone", and the
 * salons already on the platform are the ones who waited.
 *
 * The grant is idempotent on the welcome_bonus transaction row, so re-running
 * this cannot double anyone's balance.
 */
return new class extends Migration
{
    private const DEFAULT_COINS = 2300;

    public function up(): void
    {
        $coins = $this->ensureSetting();

        if ($coins < 1) {
            return;
        }

        $coinValue = (float) (DB::table('platform_policy_settings')
            ->where('setting_key', 'coin_value_inr')
            ->value('setting_value') ?? 1.0);

        // Salons that already had a bonus — none on the first run, but this
        // keeps a repeat run harmless.
        $alreadyGranted = DB::table('wallet_transactions')
            ->where('type', 'welcome_bonus')
            ->pluck('salon_id')
            ->all();

        $salons = DB::table('salons')
            ->where('status', 'active')
            ->whereNull('deleted_at')
            ->whereNotIn('id', $alreadyGranted ?: ['-'])
            ->pluck('id');

        foreach ($salons as $salonId) {
            $this->grant($salonId, $coins, $coinValue);
        }
    }

    /**
     * Writes the setting only if SuperAdmin has not already chosen a value, so
     * re-running never resets a deliberate change back to 2300.
     */
    private function ensureSetting(): int
    {
        $existing = DB::table('platform_policy_settings')
            ->where('setting_key', 'welcome_bonus_coins')
            ->value('setting_value');

        if ($existing !== null) {
            return (int) $existing;
        }

        // The column demands an author. Nobody chose this value, so it is
        // attributed to whichever SuperAdmin account exists — or skipped
        // entirely on a database with no users yet, where the model default
        // still answers for the key.
        $author = DB::table('users')->where('role', 'superadmin')->value('id');

        if (! $author) {
            return self::DEFAULT_COINS;
        }

        DB::table('platform_policy_settings')->insert([
            'setting_key' => 'welcome_bonus_coins',
            'setting_value' => (string) self::DEFAULT_COINS,
            'data_type' => 'integer',
            'description' => 'Free coins given to a salon when SuperAdmin approves it',
            'updated_by' => $author,
        ]);

        return self::DEFAULT_COINS;
    }

    private function grant(string $salonId, int $coins, float $coinValue): void
    {
        $balance = (int) (DB::table('salon_wallets')
            ->where('salon_id', $salonId)
            ->value('coin_balance') ?? 0);

        $newBalance = $balance + $coins;

        DB::table('salon_wallets')->updateOrInsert(
            ['salon_id' => $salonId],
            ['coin_balance' => $newBalance]
        );

        DB::table('wallet_transactions')->insert([
            'id' => (string) Str::uuid(),
            'salon_id' => $salonId,
            'type' => 'welcome_bonus',
            'coins' => $coins,
            'balance_after' => $newBalance,
            'coin_value_snapshot' => $coinValue,
            'note' => 'Welcome bonus on approval',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    /**
     * Takes back exactly what was given: the bonus rows, and the coins they
     * added. A salon that has already spent some of its bonus is floored at
     * zero rather than pushed negative.
     */
    public function down(): void
    {
        $grants = DB::table('wallet_transactions')
            ->where('type', 'welcome_bonus')
            ->get(['salon_id', 'coins']);

        foreach ($grants as $grant) {
            $balance = (int) (DB::table('salon_wallets')
                ->where('salon_id', $grant->salon_id)
                ->value('coin_balance') ?? 0);

            DB::table('salon_wallets')
                ->where('salon_id', $grant->salon_id)
                ->update(['coin_balance' => max(0, $balance - (int) $grant->coins)]);
        }

        DB::table('wallet_transactions')->where('type', 'welcome_bonus')->delete();
        DB::table('platform_policy_settings')->where('setting_key', 'welcome_bonus_coins')->delete();
    }
};
