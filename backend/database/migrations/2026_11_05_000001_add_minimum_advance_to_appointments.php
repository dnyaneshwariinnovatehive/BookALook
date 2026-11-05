<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The minimum advance a booking's services asked for, kept even when the
 * customer chose to pay more.
 *
 * A customer who pays the full amount by choice (payment_option
 * `full_optional`) gets everything above this back on cancellation; only this
 * part follows each service's will_refund_advance_if_cancelled rule.
 *
 * Additive only: no existing row is changed. Null on older bookings, which
 * were never paid in full by choice.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('appointments', function (Blueprint $table) {
            $table->decimal('minimum_advance', 12, 2)->nullable()->after('advance_due');
        });
    }

    public function down(): void
    {
        Schema::table('appointments', function (Blueprint $table) {
            $table->dropColumn('minimum_advance');
        });
    }
};
