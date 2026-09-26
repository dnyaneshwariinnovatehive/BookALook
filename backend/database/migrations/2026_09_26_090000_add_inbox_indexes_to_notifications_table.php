<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    /**
     * The inbox is read as "this user's notifications, newest first" and the
     * unread filter is asked for on every open. Without these two indexes the
     * whole table is scanned and sorted per request, and the sort is exactly
     * what the customer feels as the inbox getting slow.
     */
    public function up(): void
    {
        Schema::table('notifications', function (Blueprint $table) {
            $table->index(['user_id', 'created_at'], 'notifications_user_id_created_at_index');
            $table->index(['user_id', 'is_read'], 'notifications_user_id_is_read_index');
        });
    }

    public function down(): void
    {
        Schema::table('notifications', function (Blueprint $table) {
            $table->dropIndex('notifications_user_id_created_at_index');
            $table->dropIndex('notifications_user_id_is_read_index');
        });
    }
};
