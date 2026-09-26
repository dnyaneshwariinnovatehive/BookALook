<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A stable identity for "this notification, for this reason, once".
     *
     * The scheduled reminders need to be idempotent, and the only honest way to
     * be idempotent is to let the database refuse the second one. `CheckSubscriptions`
     * does this by re-querying for today's row and hoping nothing else is running;
     * a unique key turns that race into a constraint violation that costs one
     * insert and no duplicate.
     *
     * Nullable, and the unique index is partial. PostgreSQL already permits many
     * NULLs under a unique index, and a partial index keeps the index small
     * instead of carrying a NULL entry for every ordinary notification ever
     * written.
     */
    public function up(): void
    {
        Schema::table('notifications', function (Blueprint $table) {
            $table->string('dedupe_key', 120)->nullable()->after('data');
        });

        // A partial unique index, so the column is a genuine guarantee rather
        // than a convention. Built with a raw statement because Blueprint's
        // `unique()` cannot express WHERE.
        //
        // No plain index alongside it: a unique index is already an index, and a
        // second one over the same column would only make every write slower.
        // The partial form also keeps the index off the overwhelming majority of
        // rows, since a dedupe key is set only by the handful of events that can
        // be asked to happen twice.
        //
        // Supported by PostgreSQL and by SQLite, which is what the test suite
        // runs on, so the same migration applies to both.
        DB::statement(
            'CREATE UNIQUE INDEX notifications_dedupe_key_unique'
            .' ON notifications (dedupe_key) WHERE dedupe_key IS NOT NULL'
        );
    }

    public function down(): void
    {
        DB::statement('DROP INDEX IF EXISTS notifications_dedupe_key_unique');

        Schema::table('notifications', function (Blueprint $table) {
            $table->dropColumn('dedupe_key');
        });
    }
};
