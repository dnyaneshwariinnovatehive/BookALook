<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('subscription_payment_requests', function (Blueprint $table) {
            // Drop foreign key first if SQLite allows it or just change type
            $table->uuid('salon_id')->change();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('subscription_payment_requests', function (Blueprint $table) {
            $table->unsignedBigInteger('salon_id')->change();
        });
    }
};
