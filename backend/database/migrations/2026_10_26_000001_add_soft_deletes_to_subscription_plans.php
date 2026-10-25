<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A retired plan is hidden, not erased: salons that once bought it still have
 * subscriptions and payment requests pointing at it, and the foreign key from
 * salon_subscriptions would refuse a real delete anyway.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('subscription_plans', function (Blueprint $table) {
            $table->softDeletes();
        });
    }

    public function down(): void
    {
        Schema::table('subscription_plans', function (Blueprint $table) {
            $table->dropSoftDeletes();
        });
    }
};
