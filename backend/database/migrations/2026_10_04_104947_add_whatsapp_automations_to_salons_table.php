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
            $table->boolean('whatsapp_25_days_enabled')->default(false)->after('commission_rate_effective_from');
            $table->boolean('whatsapp_birthday_enabled')->default(false)->after('whatsapp_25_days_enabled');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('salons', function (Blueprint $table) {
            $table->dropColumn(['whatsapp_25_days_enabled', 'whatsapp_birthday_enabled']);
        });
    }
};
