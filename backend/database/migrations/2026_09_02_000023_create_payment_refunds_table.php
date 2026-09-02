<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('payment_refunds', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('payment_id')->constrained('payments')->onDelete('cascade');
            $table->foreignUuid('appointment_id')->constrained('appointments');
            $table->decimal('amount', 12, 2);
            $table->string('reason', 255);
            $table->string('gateway_refund_id', 150)->nullable()->unique();
            $table->string('status', 30)->default('pending');
            $table->foreignUuid('initiated_by')->nullable()->constrained('users');
            $table->timestamp('processed_at')->nullable();
            $table->text('failure_reason')->nullable();
            $table->jsonb('metadata')->nullable();
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('payment_refunds'); }
};
