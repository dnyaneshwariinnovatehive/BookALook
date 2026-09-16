<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Makes reviews and complaints usable as a feedback system.
 *
 * Neither table was ever written to by the app — they were created, seeded, and
 * left. Two things were missing before they could carry real traffic.
 *
 * A review with no time on it cannot be ordered, cannot be shown as "3 weeks
 * ago", and cannot tell a salon owner whether a run of one-star ratings is
 * happening now or happened last winter. Existing rows are dated from the
 * appointment they belong to, which is the closest thing to the truth we have.
 *
 * A complaint needs to record what SuperAdmin actually did about it, not just
 * that it was dealt with. "Resolved" says nothing to the salon that got
 * suspended or the customer who reported them.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('reviews', function (Blueprint $table) {
            $table->timestamps();
        });

        // Dated from the appointment, since that is when the visit happened and
        // a review can only follow it.
        DB::statement('
            UPDATE reviews
               SET created_at = (
                       SELECT a.appointment_date
                         FROM appointments a
                        WHERE a.id = reviews.appointment_id
                   ),
                   updated_at = (
                       SELECT a.appointment_date
                         FROM appointments a
                        WHERE a.id = reviews.appointment_id
                   )
             WHERE created_at IS NULL
        ');

        Schema::table('complaints', function (Blueprint $table) {
            $table->timestamps();

            // What SuperAdmin did, kept apart from the status so "resolved"
            // does not have to mean three different things.
            $table->string('action_taken', 20)->nullable()->after('status');

            // The words that went with it — the warning the salon was sent, or
            // the reason it was suspended. Read back to the customer as the
            // outcome of their report.
            $table->text('resolution_note')->nullable()->after('action_taken');
        });
    }

    public function down(): void
    {
        Schema::table('reviews', function (Blueprint $table) {
            $table->dropTimestamps();
        });

        Schema::table('complaints', function (Blueprint $table) {
            $table->dropTimestamps();
            $table->dropColumn(['action_taken', 'resolution_note']);
        });
    }
};
