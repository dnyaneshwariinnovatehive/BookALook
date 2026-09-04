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
        Schema::table('salon_subscriptions', function (Blueprint $table) {
            $table->dropColumn('feature_level');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('salon_subscriptions', function (Blueprint $table) {
            $table->string('feature_level', 20)->nullable();
        });
    }
};
