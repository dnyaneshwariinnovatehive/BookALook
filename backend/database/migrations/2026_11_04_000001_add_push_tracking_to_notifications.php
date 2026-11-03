<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CREATE INDEX CONCURRENTLY cannot run inside a transaction block.
     */
    public $withinTransaction = false;

    /**
     * Makes a queued push recoverable.
     *
     * A notification_deliveries row is only written once FCM has answered, so
     * a push job lost before it ran (queue outage, worker killed, Redis
     * restart) used to leave no trace: nothing showed a push was owed. Now:
     *
     *   push_queued_at  set when the push is queued (and on each re-queue);
     *   push_done_at    set when the push job has finished with it — sent,
     *                   skipped (no device, switched off) or given up;
     *   push_sweeps     how many times the recovery sweep re-queued it.
     *
     * queued and not done after 5 minutes = lost; the sweep queues it again,
     * at most 3 times. Rows written before this migration have both NULL and
     * are never touched.
     *
     * Locking: adding nullable columns, and a column with a constant default,
     * only changes the catalogue in PostgreSQL (no table rewrite). The partial
     * index is built CONCURRENTLY, so inserts carry on while it builds.
     */
    public function up(): void
    {
        Schema::table('notifications', function (Blueprint $table) {
            $table->timestamp('push_queued_at')->nullable();
            $table->timestamp('push_done_at')->nullable();
            $table->unsignedSmallInteger('push_sweeps')->default(0);
        });

        $concurrently = DB::getDriverName() === 'pgsql' ? 'CONCURRENTLY ' : '';

        DB::statement(
            "CREATE INDEX {$concurrently}IF NOT EXISTS notifications_push_owed_idx"
            .' ON notifications (push_queued_at) WHERE push_done_at IS NULL AND push_queued_at IS NOT NULL'
        );
    }

    public function down(): void
    {
        DB::statement('DROP INDEX IF EXISTS notifications_push_owed_idx');

        Schema::table('notifications', function (Blueprint $table) {
            $table->dropColumn(['push_queued_at', 'push_done_at', 'push_sweeps']);
        });
    }
};
