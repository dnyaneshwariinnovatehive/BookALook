<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('appointments', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('salon_id')->constrained('salons')->onDelete('cascade');
            $table->foreignUuid('customer_id')->nullable()->constrained('users')->onDelete('set null');
            $table->foreignUuid('appointed_provider_id')->constrained('service_providers');
            $table->foreignUuid('serving_provider_id')->nullable()->constrained('service_providers');
            $table->string('booking_source', 20)->default('online');
            $table->date('appointment_date');
            $table->time('start_time');
            $table->time('end_time');
            $table->string('status', 30)->default('pending_payment');
            $table->string('payment_option', 20)->default('advance_only');
            $table->decimal('total_amount', 12, 2)->default(0.00);
            $table->decimal('advance_amount', 12, 2)->default(0.00);
            $table->decimal('balance_amount', 12, 2)->default(0.00);
            $table->decimal('final_billed_amount', 12, 2)->nullable();
            $table->string('walk_in_customer_name', 150)->nullable();
            $table->string('walk_in_customer_phone', 20)->nullable();
            $table->char('qr_token_hash', 64)->nullable();
            $table->timestamp('qr_generated_at')->nullable();
            $table->timestamp('qr_expires_at')->nullable();
            $table->timestamp('qr_verified_at')->nullable();
            $table->foreignUuid('qr_verified_by')->nullable()->constrained('users');
            $table->string('verification_method', 20)->default('qr');
            $table->string('cancelled_by', 20)->nullable();
            $table->foreignUuid('cancelled_by_user_id')->nullable()->constrained('users');
            $table->string('cancellation_reason', 255)->nullable();
            $table->timestamp('cancelled_at')->nullable();
            $table->foreignUuid('rescheduled_from_id')->nullable()->constrained('appointments');
            $table->string('reschedule_reason', 255)->nullable();
            $table->timestamp('started_at')->nullable();
            $table->timestamp('completed_at')->nullable();
            $table->timestamp('no_show_at')->nullable();
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('appointments'); }
};
