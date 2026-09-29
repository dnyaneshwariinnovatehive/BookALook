<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The invoice BookALook issues to a salon owner when a cycle of money is settled.
 *
 * The mirror image of `invoices`: a customer invoice says what a customer owes,
 * this says what the platform paid a salon for a week or a month and what came
 * off it. Same rules for the same reasons —
 *
 *  - Frozen. Every figure is a copy of the payout as it stood the instant the
 *    money moved, plus a `template` copy of the branding. Re-deriving it from
 *    `salon_payouts` would let a later recalculation, a coin redemption, or a
 *    SuperAdmin logo change rewrite a document the owner has already filed.
 *  - One per payout. Unique on `payout_id`, so a repeated distribute attempt
 *    cannot mint a second statement for the same settlement.
 *
 * It is a separate table rather than a second `document_type` on `invoices`
 * because the two documents share no columns: a customer invoice is itemised by
 * service, this one is a statement with deductions, and widening the shared
 * table to hold both shapes would mean nullable-everything for the sake of one
 * number series. They do share the settings table, so they look alike.
 */
return new class extends Migration {
    public function up(): void {
        Schema::create('settlement_invoices', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('payout_id')->unique()->constrained('salon_payouts')->cascadeOnDelete();
            $table->string('invoice_number', 60)->unique();

            $table->timestamp('issued_at');
            $table->string('currency', 3)->default('INR');

            // Who it is addressed to, as they were when it was issued. The
            // owner is the bill-to here; the salon is the party being settled.
            $table->foreignUuid('salon_id')->constrained('salons')->cascadeOnDelete();
            $table->string('salon_name', 150)->nullable();
            $table->text('salon_address')->nullable();
            $table->string('salon_phone', 20)->nullable();
            $table->string('owner_name', 150)->nullable();

            // The period being settled and how the salon pays, which is what
            // decides whether the cycle is a week or a month.
            $table->string('billing_type', 20)->default('subscription');
            $table->string('cycle_type', 10);
            $table->date('cycle_start_date');
            $table->date('cycle_end_date');
            $table->string('cycle_label', 100)->nullable();

            // Frozen statement lines: name / detail / amount, deductions signed.
            $table->json('line_items');

            $table->unsignedInteger('appointments_count')->default(0);
            $table->decimal('appointment_revenue', 12, 2)->default(0.00);

            // The same five components PayoutService::net() adds up, kept
            // separately so the statement can be read line by line and audited
            // against the payout without trusting the arithmetic on the page.
            $table->decimal('advances_held', 12, 2)->default(0.00);
            $table->decimal('commission_deducted', 12, 2)->default(0.00);
            $table->decimal('commission_percentage', 5, 2)->default(0.00);
            $table->decimal('refund_adjustment', 12, 2)->default(0.00);
            $table->decimal('wallet_redeemed_amount', 12, 2)->default(0.00);
            $table->decimal('net_amount', 12, 2)->default(0.00);

            // How the money left, so the owner can match this against a bank
            // line. Optional: a payout distributed in cash has no reference.
            $table->string('distribution_reference', 150)->nullable();
            $table->timestamp('paid_at')->nullable();

            // The branding as it stood when this was issued.
            $table->json('template');

            $table->timestamps();

            // Every document for one salon, newest first. This is the query the
            // owner's invoice list makes.
            $table->index(['salon_id', 'issued_at']);
        });
    }
    public function down(): void { Schema::dropIfExists('settlement_invoices'); }
};
