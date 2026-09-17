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
        Schema::table('salon_enquiries', function (Blueprint $table) {
            $table->string('street_address', 255)->nullable()->after('sub_area_id');
            $table->string('pincode', 20)->nullable()->after('street_address');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('salon_enquiries', function (Blueprint $table) {
            $table->dropColumn(['street_address', 'pincode']);
        });
    }
};
