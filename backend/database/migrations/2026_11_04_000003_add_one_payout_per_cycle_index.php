<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /** CREATE INDEX CONCURRENTLY cannot run inside a transaction block. */
    public $withinTransaction = false;

    /** Cycles from this date on are protected; earlier ones are left as they are. */
    private const FROM = '2026-10-01';

    /**
     * One payout per salon, cycle type and cycle start — for cycles from
     * 2026-10-01 on.
     *
     * PayoutService recalculates that one row in place (and freezes it once
     * approved, distributed or paid against), so the three columns are one
     * logical cycle. Its check-then-insert was not atomic: the 04:00 schedule
     * and SuperAdmin's "generate" running together could each insert a row.
     *
     * Older cycles are excluded on purpose: production has 14 groups of
     * duplicates from June–September 2026 (test/demo salons, some approved or
     * distributed). Financial rows are never deleted or merged here; those
     * stay exactly as they are, and are listed by app:integrity-report.
     *
     * Pre-check: refuses if any duplicates exist in the protected range.
     * Locking: built CONCURRENTLY (no write lock) on PostgreSQL; a failed
     * concurrent build leaves an INVALID index, which down() drops.
     */
    public function up(): void
    {
        $dupes = DB::table('salon_payouts')
            ->select('salon_id', 'cycle_type', 'cycle_start_date')
            ->where('cycle_start_date', '>=', self::FROM)
            ->groupBy('salon_id', 'cycle_type', 'cycle_start_date')
            ->havingRaw('count(*) > 1')
            ->limit(20)
            ->get();

        if ($dupes->isNotEmpty()) {
            $list = $dupes->map(fn ($d) => "{$d->salon_id}/{$d->cycle_type}/{$d->cycle_start_date}")->implode('; ');
            throw new RuntimeException('Duplicate payout cycles exist from ' . self::FROM . ', reconcile them first: ' . $list);
        }

        $concurrently = DB::getDriverName() === 'pgsql' ? 'CONCURRENTLY ' : '';

        DB::statement(
            "CREATE UNIQUE INDEX {$concurrently}IF NOT EXISTS salon_payouts_one_per_cycle"
            . ' ON salon_payouts (salon_id, cycle_type, cycle_start_date)'
            . " WHERE cycle_start_date >= '" . self::FROM . "'"
        );
    }

    public function down(): void
    {
        DB::statement('DROP INDEX IF EXISTS salon_payouts_one_per_cycle');
    }
};
