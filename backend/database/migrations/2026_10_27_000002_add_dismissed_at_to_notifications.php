<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A notification the person deleted from their inbox.
 *
 * Hidden rather than removed: the row is also the de-duplication record that
 * stops the same reminder being sent twice, so dropping it would invite the
 * very notice they just deleted to come back. The nightly prune removes it for
 * good on the usual retention.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('notifications', function (Blueprint $table) {
            $table->timestamp('dismissed_at')->nullable();
            $table->index(['user_id', 'dismissed_at', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::table('notifications', function (Blueprint $table) {
            $table->dropIndex(['user_id', 'dismissed_at', 'created_at']);
            $table->dropColumn('dismissed_at');
        });
    }
};
