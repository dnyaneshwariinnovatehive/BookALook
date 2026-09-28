<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * One invoice per confirmed appointment.
 *
 * Almost every money column here is a copy of something on the appointment or
 * its service lines, and that is the point. An invoice is a statement made at a
 * moment in time: if it read live from `appointments` and `appointment_services`
 * then a mid-visit extra service, a cancellation, or a salon renaming itself
 * would silently rewrite a document the customer had already been shown and
 * quite possibly printed. The line items and the totals are frozen into JSON at
 * issue time, and `template` freezes the branding alongside them.
 *
 * Unique on `appointment_id` because a retry of a payment confirmation must not
 * produce a second document for one visit — the service treats a repeat as
 * "already issued" and hands back the original.
 */
return new class extends Migration {
    public function up(): void {
        Schema::create('invoices', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('appointment_id')->unique()->constrained('appointments')->cascadeOnDelete();
            $table->string('invoice_number', 60)->unique();

            $table->timestamp('issued_at');
            $table->string('currency', 3)->default('INR');

            // Who it is addressed to, as they were when it was issued.
            $table->string('bill_to_name', 150)->nullable();
            $table->string('bill_to_phone', 20)->nullable();
            $table->string('bill_to_email', 150)->nullable();

            // Who performed the service.
            $table->string('salon_name', 150)->nullable();
            $table->text('salon_address')->nullable();
            $table->string('provider_name', 150)->nullable();

            $table->date('appointment_date');
            $table->time('start_time');
            $table->time('end_time');

            // name / kind / price / duration per line, frozen.
            $table->json('line_items');

            $table->decimal('subtotal', 12, 2)->default(0.00);
            $table->decimal('advance_paid', 12, 2)->default(0.00);
            $table->decimal('balance_due', 12, 2)->default(0.00);
            $table->decimal('total', 12, 2)->default(0.00);

            // The branding as it stood when this was issued, so editing the
            // format in SuperAdmin changes future invoices only.
            $table->json('template');

            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('invoices'); }
};
