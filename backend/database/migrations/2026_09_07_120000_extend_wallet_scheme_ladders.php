<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Turns the reward ladder into bands.
 *
 * "The first 250 completed appointments earn X, the next 100 earn more" is a
 * range, not a single milestone — the original `appointments_required` column
 * could only express "when the count hits exactly N". Each rung now carries the
 * band it covers, with an open-ended last rung.
 *
 * `appointments_required` is kept and still written (equal to the band's start)
 * so nothing reading the old column breaks.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('wallet_schemes', function (Blueprint $table) {
            $table->text('description')->nullable()->after('name');

            // per_appointment: every appointment in the band earns the band's
            // coins. on_completion: a lump lands when the band is finished.
            $table->string('award_mode', 20)->default('per_appointment')->after('description');

            // Several schemes exist over time; these decide which one is in force.
            $table->date('starts_on')->nullable()->after('is_active');
            $table->date('ends_on')->nullable()->after('starts_on');
        });

        Schema::table('wallet_scheme_tiers', function (Blueprint $table) {
            $table->integer('appointments_from')->default(1)->after('tier_order');
            // null on the final rung, which never ends.
            $table->integer('appointments_to')->nullable()->after('appointments_from');
        });

        // Existing rungs were "reach N" milestones; treat N as the band start.
        DB::table('wallet_scheme_tiers')->update([
            'appointments_from' => DB::raw('appointments_required'),
        ]);
    }

    public function down(): void
    {
        Schema::table('wallet_scheme_tiers', function (Blueprint $table) {
            $table->dropColumn(['appointments_from', 'appointments_to']);
        });

        Schema::table('wallet_schemes', function (Blueprint $table) {
            $table->dropColumn(['description', 'award_mode', 'starts_on', 'ends_on']);
        });
    }
};
