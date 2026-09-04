<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /** Align existing installations with the UUID key used by subscription_plans. */
    public function up(): void
    {
        Schema::table('subscription_payment_requests', function (Blueprint $table) {
            $table->uuid('subscription_plan_id')->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('subscription_payment_requests', function (Blueprint $table) {
            $table->unsignedBigInteger('subscription_plan_id')->nullable()->change();
        });
    }
};
