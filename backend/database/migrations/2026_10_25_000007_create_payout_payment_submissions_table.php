<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A salon paying BookALook what a payout says it owes.
 *
 * When a Commission Model salon's commission is more than the advances the
 * platform held, the payout goes negative and the salon owes the difference.
 * It pays by scanning BookALook's QR, uploads the screenshot, and SuperAdmin
 * verifies it — the same way plans are bought.
 *
 * Submitting freezes the payout (locked_at), so the amount paid can never be
 * recalculated underneath the owner; anything that turns up later goes into
 * the next payout instead.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('payout_payment_submissions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('salon_payout_id')->constrained('salon_payouts')->cascadeOnDelete();
            $table->foreignUuid('salon_id')->constrained('salons')->cascadeOnDelete();
            // What was owed when the owner paid; the payout is frozen from then.
            $table->decimal('amount', 12, 2);
            $table->string('screenshot_url', 500);
            $table->string('transaction_id', 150)->nullable();
            $table->text('note')->nullable();
            $table->string('status', 20)->default('pending'); // pending, approved, rejected
            $table->foreignUuid('submitted_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignUuid('reviewed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('reviewed_at')->nullable();
            $table->text('rejection_reason')->nullable();
            $table->timestamps();

            $table->index(['salon_payout_id', 'status']);
            $table->index(['status', 'created_at']);
        });

        Schema::table('salon_payouts', function (Blueprint $table) {
            // Set when the salon submits a payment for what it owes. A locked
            // payout is never recalculated.
            $table->timestamp('locked_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('salon_payouts', function (Blueprint $table) {
            $table->dropColumn('locked_at');
        });

        Schema::dropIfExists('payout_payment_submissions');
    }
};
