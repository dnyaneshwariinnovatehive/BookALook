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
        Schema::table('subscription_plans', function (Blueprint $table) {
            $table->integer('validity_days')->default(30)->after('price');
        });

        Schema::table('salons', function (Blueprint $table) {
            $table->boolean('commission_opt_in')->default(false)->after('status');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('subscription_plans', function (Blueprint $table) {
            $table->dropColumn('validity_days');
        });

        Schema::table('salons', function (Blueprint $table) {
            $table->dropColumn('commission_opt_in');
        });
    }
};
