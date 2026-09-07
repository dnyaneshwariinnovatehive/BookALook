<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Who took the money at the counter, how, and when — plus why an appointment
 * was started without the customer's QR.
 *
 * The payments table already records the transaction; these columns put the
 * answer on the appointment itself so the salon's own screens and any dispute
 * do not have to join through the ledger to find out who closed the job.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('appointments', function (Blueprint $table) {
            $table->timestamp('payment_collected_at')->nullable()->after('final_billed_amount');
            $table->foreignUuid('payment_collected_by')->nullable()->after('payment_collected_at')
                ->constrained('users')->nullOnDelete();
            $table->string('payment_mode', 20)->nullable()->after('payment_collected_by');

            // Set when staff start a session without scanning, e.g. the
            // customer's phone is dead. verification_method already records
            // that it happened; this records why.
            $table->string('manual_check_in_reason', 255)->nullable()->after('verification_method');
        });
    }

    public function down(): void
    {
        Schema::table('appointments', function (Blueprint $table) {
            $table->dropConstrainedForeignId('payment_collected_by');
            $table->dropColumn(['payment_collected_at', 'payment_mode', 'manual_check_in_reason']);
        });
    }
};
