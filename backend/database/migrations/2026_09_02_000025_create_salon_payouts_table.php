<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('salon_payouts', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('salon_id')->constrained('salons')->onDelete('cascade');
            $table->date('cycle_week_start_date');
            $table->date('cycle_week_end_date');
            $table->decimal('gross_amount', 12, 2)->default(0.00);
            $table->decimal('commission_percentage_snapshot', 5, 2)->default(0.00);
            $table->decimal('commission_deducted', 12, 2)->default(0.00);
            $table->decimal('wallet_redeemed_amount', 12, 2)->default(0.00);
            $table->decimal('refund_adjustment', 12, 2)->default(0.00);
            $table->decimal('net_amount', 12, 2)->default(0.00);
            $table->string('status', 30)->default('pending');
            $table->timestamp('calculated_at')->nullable();
            $table->foreignUuid('approved_by')->nullable()->constrained('users');
            $table->timestamp('approved_at')->nullable();
            $table->foreignUuid('distributed_by')->nullable()->constrained('users');
            $table->timestamp('distributed_at')->nullable();
            $table->string('distribution_reference', 150)->nullable();
            $table->text('notes')->nullable();
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('salon_payouts'); }
};
