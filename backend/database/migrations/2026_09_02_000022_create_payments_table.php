<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('payments', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('appointment_id')->constrained('appointments')->onDelete('cascade');
            $table->foreignUuid('payment_order_id')->nullable()->constrained('payment_orders')->onDelete('set null');
            $table->decimal('amount', 12, 2);
            $table->char('currency', 3)->default('INR');
            $table->string('payment_type', 20); // advance, full, balance, other
            $table->string('payment_mode', 20)->default('online');
            $table->string('gateway', 30)->nullable();
            $table->string('gateway_transaction_id', 150)->nullable();
            $table->string('gateway_signature', 500)->nullable();
            $table->string('status', 30)->default('pending');
            $table->text('failure_reason')->nullable();
            $table->timestamp('paid_at')->nullable();
            $table->string('idempotency_key', 100)->unique()->nullable();
            $table->jsonb('metadata')->nullable();
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('payments'); }
};
