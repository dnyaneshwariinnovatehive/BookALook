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
        Schema::table('salons', function (Blueprint $table) {
            $table->uuid('city_id')->nullable()->constrained('cities')->onDelete('set null');
        });

        Schema::table('salon_enquiries', function (Blueprint $table) {
            $table->uuid('city_id')->nullable()->constrained('cities')->onDelete('set null');
        });

        Schema::table('banners', function (Blueprint $table) {
            $table->uuid('target_city_id')->nullable()->constrained('cities')->onDelete('set null');
        });

        // Drop the old string columns
        Schema::table('salons', function (Blueprint $table) {
            $table->dropIndex(['city']);
            $table->dropColumn('city');
        });

        Schema::table('salon_enquiries', function (Blueprint $table) {
            $table->dropColumn('city');
        });

        Schema::table('banners', function (Blueprint $table) {
            $table->dropColumn('target_city');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('salons', function (Blueprint $table) {
            $table->string('city', 100)->nullable();
            $table->dropForeign(['city_id']);
            $table->dropColumn('city_id');
        });

        Schema::table('salon_enquiries', function (Blueprint $table) {
            $table->string('city', 100)->nullable();
            $table->dropForeign(['city_id']);
            $table->dropColumn('city_id');
        });

        Schema::table('banners', function (Blueprint $table) {
            $table->string('target_city', 100)->nullable();
            $table->dropForeign(['target_city_id']);
            $table->dropColumn('target_city_id');
        });
    }
};
