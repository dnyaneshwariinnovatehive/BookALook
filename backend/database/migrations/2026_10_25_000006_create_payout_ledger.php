<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Payouts settle bookings, one booking in exactly one payout.
 *
 * Until now a payout re-derived its money from "completed appointments dated
 * in this cycle", which paid the same advance twice when a salon switched
 * model mid-month, never paid a booking completed after its cycle closed, and
 * took refunds of cancelled bookings off other customers' advances.
 *
 * Now every booking a payout settles is a row in salon_payout_items, and every
 * refund it accounts for points at it. A booking already settled can never be
 * picked up again; one nobody has settled yet is picked up by the next payout,
 * whatever its cycle.
 *
 * Existing payouts are recorded as they stood, so nothing already paid is paid
 * again. The new rules start, per salon, from its oldest payout still open —
 * or from today when it has none — so they never reach back into history.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('salon_payout_items', function (Blueprint $table) {
            // booking: a booking settled in this payout. late_refund: a refund
            // on a booking an earlier payout already settled.
            $table->string('kind', 20)->default('booking')->after('salon_payout_id');
            $table->foreignUuid('payment_refund_id')->nullable()->after('payment_id')
                ->constrained('payment_refunds')->nullOnDelete();
            $table->string('appointment_status', 20)->nullable();
            $table->decimal('commission_base', 12, 2)->default(0);
            $table->decimal('commission_rate', 5, 2)->default(0);
            $table->index(['appointment_id', 'kind']);
        });

        Schema::table('payment_refunds', function (Blueprint $table) {
            // The payout that accounted for this refund, once one has.
            $table->foreignUuid('salon_payout_id')->nullable()->constrained('salon_payouts')->nullOnDelete();
        });

        Schema::table('salons', function (Blueprint $table) {
            // Bookings before this date were settled the old way and are left
            // alone. Null means everything counts — a salon that joins after
            // this change has no history to protect.
            $table->date('payout_ledger_since')->nullable();
        });

        // One booking, one settlement — enforced by the database, not just the
        // code. Partial index: PostgreSQL and SQLite both support it.
        if (in_array(DB::getDriverName(), ['pgsql', 'sqlite'], true)) {
            DB::statement(
                "CREATE UNIQUE INDEX salon_payout_items_one_booking_settlement"
                ." ON salon_payout_items (appointment_id) WHERE kind = 'booking'"
            );
        }

        $this->backfill();
    }

    private function backfill(): void
    {
        $today = now()->toDateString();

        // Where the new rules start for each salon that already has payouts.
        $salonIds = DB::table('salon_payouts')->distinct()->pluck('salon_id');
        foreach ($salonIds as $salonId) {
            $oldestOpen = DB::table('salon_payouts')
                ->where('salon_id', $salonId)
                ->where('status', '!=', 'distributed')
                ->min('cycle_start_date');

            DB::table('salons')->where('id', $salonId)->update([
                'payout_ledger_since' => $oldestOpen ?? $today,
            ]);
        }

        // Salons with no payouts yet: nothing before today is reopened.
        DB::table('salons')->whereNull('payout_ledger_since')->update(['payout_ledger_since' => $today]);

        // Record what each paid-out payout settled, the way it settled it, so a
        // booking it paid can never be paid again.
        $distributed = DB::table('salon_payouts')->where('status', 'distributed')->orderBy('cycle_start_date')->get();
        foreach ($distributed as $payout) {
            $appointments = DB::table('appointments')
                ->where('salon_id', $payout->salon_id)
                ->where('status', 'completed')
                ->whereBetween('appointment_date', [$payout->cycle_start_date, $payout->cycle_end_date])
                ->get(['id', 'status', 'total_amount', 'final_billed_amount', 'advance_amount']);

            foreach ($appointments as $a) {
                $already = DB::table('salon_payout_items')
                    ->where('appointment_id', $a->id)
                    ->where('kind', 'booking')
                    ->exists();
                if ($already) {
                    continue;
                }

                $billed = (float) ($a->final_billed_amount ?? $a->total_amount);
                $rate = (float) $payout->commission_percentage_snapshot;
                $commission = round($billed * $rate / 100, 2);

                DB::table('salon_payout_items')->insert([
                    'id' => (string) \Illuminate\Support\Str::uuid(),
                    'salon_payout_id' => $payout->id,
                    'kind' => 'booking',
                    'appointment_id' => $a->id,
                    'appointment_status' => $a->status,
                    'gross_amount' => (float) $a->advance_amount,
                    'commission_base' => $billed,
                    'commission_rate' => $rate,
                    'commission_amount' => $commission,
                    'refund_amount' => 0,
                    'net_amount' => round((float) $a->advance_amount - $commission, 2),
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }

            // The old engine took refunds raised in the cycle off this payout.
            DB::table('payment_refunds')
                ->whereNull('salon_payout_id')
                ->whereIn('appointment_id', DB::table('appointments')->where('salon_id', $payout->salon_id)->select('id'))
                ->whereBetween('created_at', [$payout->cycle_start_date.' 00:00:00', $payout->cycle_end_date.' 23:59:59'])
                ->update(['salon_payout_id' => $payout->id]);
        }
    }

    public function down(): void
    {
        if (in_array(DB::getDriverName(), ['pgsql', 'sqlite'], true)) {
            DB::statement('DROP INDEX IF EXISTS salon_payout_items_one_booking_settlement');
        }

        Schema::table('salons', function (Blueprint $table) {
            $table->dropColumn('payout_ledger_since');
        });

        Schema::table('payment_refunds', function (Blueprint $table) {
            $table->dropConstrainedForeignId('salon_payout_id');
        });

        DB::table('salon_payout_items')->delete();

        Schema::table('salon_payout_items', function (Blueprint $table) {
            $table->dropIndex(['appointment_id', 'kind']);
            $table->dropConstrainedForeignId('payment_refund_id');
            $table->dropColumn(['kind', 'appointment_status', 'commission_base', 'commission_rate']);
        });
    }
};
