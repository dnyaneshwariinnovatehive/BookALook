<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Commission dues enforcement: a SuperAdmin-set ladder of actions against a
 * Commission Model salon that has not paid what it owes.
 *
 *  - Per-salon controls SuperAdmin can apply on top of the ladder.
 *  - `dues_adjustment` on a payout: money moved between a salon's payouts when
 *    what BookALook owes it is used to clear what it owes BookALook. Signed —
 *    negative on the payout it was taken from, positive on the dues it paid.
 *  - Commission salons stop locking on a date. They used to lose access when
 *    a subscription end date — pushed out only by settling a month — went by,
 *    which also locked salons BookALook simply had not paid yet. Access is now
 *    decided by actual unpaid dues, so the date is opened up for good.
 */
return new class extends Migration
{
    public const OPEN_END = '2099-12-31';

    public function up(): void
    {
        Schema::table('salons', function (Blueprint $table) {
            // A later due date SuperAdmin granted, and why.
            $table->date('dues_extended_until')->nullable();
            // Steps paused for this salon.
            $table->boolean('dues_paused')->default(false);
            // A step SuperAdmin applied by hand instead of the schedule.
            $table->string('dues_stage_override', 30)->nullable();
            $table->text('dues_override_reason')->nullable();
            // The last step the owner was told about, so each is told once.
            $table->string('dues_notified_stage', 30)->nullable();
            $table->timestamp('dues_last_reminded_at')->nullable();
        });

        Schema::table('salon_payouts', function (Blueprint $table) {
            $table->decimal('dues_adjustment', 12, 2)->default(0);
        });

        $commissionSalons = DB::table('salons')->where('commission_opt_in', true)->pluck('id');

        foreach ($commissionSalons as $salonId) {
            $latest = DB::table('salon_subscriptions')
                ->where('salon_id', $salonId)
                ->where('billing_type', 'commission')
                ->where('status', '!=', 'cancelled')
                ->orderByDesc('start_date')
                ->first();

            if ($latest) {
                DB::table('salon_subscriptions')->where('id', $latest->id)->update([
                    'status' => 'active',
                    'end_date' => self::OPEN_END,
                    'updated_at' => now(),
                ]);
            }
        }
    }

    public function down(): void
    {
        Schema::table('salon_payouts', function (Blueprint $table) {
            $table->dropColumn('dues_adjustment');
        });

        Schema::table('salons', function (Blueprint $table) {
            $table->dropColumn([
                'dues_extended_until', 'dues_paused', 'dues_stage_override',
                'dues_override_reason', 'dues_notified_stage', 'dues_last_reminded_at',
            ]);
        });
    }
};
