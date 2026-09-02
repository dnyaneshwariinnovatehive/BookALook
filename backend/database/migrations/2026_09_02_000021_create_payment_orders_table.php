<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('payment_orders', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('appointment_id')->constrained('appointments')->onDelete('cascade');
            $table->decimal('amount', 12, 2);
            $table->char('currency', 3)->default('INR');
            $table->string('gateway', 30);
            $table->string('gateway_order_id', 150)->unique();
            $table->string('status', 30)->default('created');
            $table->timestamp('expires_at')->nullable();
            $table->string('idempotency_key', 100)->unique()->nullable();
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('payment_orders'); }
};
