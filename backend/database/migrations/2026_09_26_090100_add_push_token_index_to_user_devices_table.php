<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    /**
     * A push token identifies a phone, not a person, so it has to be looked up on
     * its own — not only in the company of a user id. Registration asks "does
     * this token already belong to somebody else?" and unregister asks "which
     * row holds this token?"; both queries are by token alone.
     *
     * The existing (user_id, push_token) unique index stays. It is what stops
     * one user registering the same install twice, and this index is added
     * beside it rather than in place of it.
     */
    public function up(): void
    {
        Schema::table('user_devices', function (Blueprint $table) {
            $table->index('push_token', 'user_devices_push_token_index');
        });
    }

    public function down(): void
    {
        Schema::table('user_devices', function (Blueprint $table) {
            $table->dropIndex('user_devices_push_token_index');
        });
    }
};
