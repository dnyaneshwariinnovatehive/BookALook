<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Makes both payout records explain themselves.
 *
 * A salon receiving a net figure needs to see what it was derived from, and a
 * staff member looking at a payslip needs to see the divisor behind the
 * deduction. Neither should have to be recomputed to be understood — the
 * numbers are snapshotted at the time the record is built.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('salon_payouts', function (Blueprint $table) {
            // Commission is charged on everything the salon billed that week,
            // while gross_amount is only the part the platform is holding.
            // Keeping both makes the deduction legible.
            $table->decimal('appointment_revenue', 12, 2)->default(0.00)->after('gross_amount');
            $table->unsignedInteger('appointments_count')->default(0)->after('appointment_revenue');
            $table->string('billing_type', 20)->default('flat')->after('appointments_count');
        });

        Schema::table('salary_payouts', function (Blueprint $table) {
            // The divisor behind the daily rate, so a deduction can be checked.
            $table->unsignedSmallInteger('working_days_in_month')->default(0)->after('commission_earned');
            $table->decimal('daily_rate', 12, 2)->default(0.00)->after('working_days_in_month');
            $table->decimal('paid_leave_days', 4, 1)->default(0.0)->after('daily_rate');
            $table->timestamp('calculated_at')->nullable()->after('total_payable');
        });
    }

    public function down(): void
    {
        Schema::table('salon_payouts', function (Blueprint $table) {
            $table->dropColumn(['appointment_revenue', 'appointments_count', 'billing_type']);
        });

        Schema::table('salary_payouts', function (Blueprint $table) {
            $table->dropColumn(['working_days_in_month', 'daily_rate', 'paid_leave_days', 'calculated_at']);
        });
    }
};
