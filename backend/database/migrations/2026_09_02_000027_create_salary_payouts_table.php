<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('salary_payouts', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('provider_id')->constrained('service_providers')->onDelete('cascade');
            $table->foreignUuid('salon_id')->constrained('salons');
            $table->date('salary_month');
            $table->decimal('base_salary_snapshot', 12, 2)->default(0.00);
            $table->decimal('commission_percentage_snapshot', 5, 2)->default(0.00);
            $table->decimal('commission_earned', 12, 2)->default(0.00);
            $table->decimal('unpaid_leave_days', 4, 1)->default(0.0);
            $table->decimal('unpaid_leave_deduction', 12, 2)->default(0.00);
            $table->decimal('other_adjustments', 12, 2)->default(0.00);
            $table->decimal('total_payable', 12, 2)->default(0.00);
            $table->string('status', 20)->default('pending');
            $table->foreignUuid('approved_by')->nullable()->constrained('users');
            $table->timestamp('approved_at')->nullable();
            $table->foreignUuid('paid_by')->nullable()->constrained('users');
            $table->timestamp('paid_at')->nullable();
            $table->string('payment_reference', 150)->nullable();
            $table->timestamps();
            
            $table->unique(['provider_id', 'salary_month']);
        });
    }
    public function down(): void { Schema::dropIfExists('salary_payouts'); }
};
