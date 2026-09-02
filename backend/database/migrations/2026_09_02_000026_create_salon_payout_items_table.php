<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('salon_payout_items', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('salon_payout_id')->constrained('salon_payouts')->onDelete('cascade');
            $table->foreignUuid('payment_id')->nullable()->constrained('payments');
            $table->foreignUuid('appointment_id')->nullable()->constrained('appointments');
            $table->decimal('gross_amount', 12, 2);
            $table->decimal('commission_amount', 12, 2)->default(0.00);
            $table->decimal('refund_amount', 12, 2)->default(0.00);
            $table->decimal('net_amount', 12, 2);
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('salon_payout_items'); }
};
