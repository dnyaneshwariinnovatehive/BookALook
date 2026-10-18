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
            $table->uuid('preferred_plan_id')->nullable()->after('gender_focus');
            $table->string('preferred_commercial_model', 20)->nullable()->after('preferred_plan_id');
            $table->decimal('requested_commission_percentage', 5, 2)->nullable()->after('preferred_commercial_model');
            $table->text('correction_notes')->nullable()->after('rejection_reason');
            $table->timestamp('correction_requested_at')->nullable()->after('correction_notes');
            $table->timestamp('resubmitted_at')->nullable()->after('correction_requested_at');

            $table->foreign('preferred_plan_id')
                ->references('id')
                ->on('subscription_plans')
                ->nullOnDelete();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('salons', function (Blueprint $table) {
            $table->dropForeign(['preferred_plan_id']);
            $table->dropColumn([
                'preferred_plan_id',
                'preferred_commercial_model',
                'requested_commission_percentage',
                'correction_notes',
                'correction_requested_at',
                'resubmitted_at',
            ]);
        });
    }
};
