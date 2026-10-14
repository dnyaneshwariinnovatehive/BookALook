<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     *
     * Adds customer_phone_hash to first_time_offer_redemptions and appointments
     * to support deterministic identity continuity across customer account deletion
     * and re-registration without persisting raw phone numbers.
     */
    public function up(): void
    {
        Schema::table('first_time_offer_redemptions', function (Blueprint $table) {
            $table->string('customer_phone_hash', 64)->nullable()->after('customer_id')->index();
        });

        Schema::table('appointments', function (Blueprint $table) {
            $table->string('customer_phone_hash', 64)->nullable()->after('customer_id')->index();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('appointments', function (Blueprint $table) {
            $table->dropIndex(['customer_phone_hash']);
            $table->dropColumn('customer_phone_hash');
        });

        Schema::table('first_time_offer_redemptions', function (Blueprint $table) {
            $table->dropIndex(['customer_phone_hash']);
            $table->dropColumn('customer_phone_hash');
        });
    }
};
