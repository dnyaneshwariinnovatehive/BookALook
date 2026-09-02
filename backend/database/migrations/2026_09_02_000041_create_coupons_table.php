<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('coupons', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('salon_id')->nullable()->constrained('salons')->onDelete('cascade');
            $table->string('code', 50)->unique();
            $table->string('description', 255)->nullable();
            $table->string('discount_type', 20); // percentage, fixed
            $table->decimal('discount_value', 12, 2);
            $table->decimal('max_discount_amount', 12, 2)->nullable();
            $table->decimal('minimum_order_amount', 12, 2)->default(0.00);
            $table->integer('usage_limit_total')->nullable();
            $table->integer('usage_limit_per_customer')->default(1);
            $table->timestamp('valid_from');
            $table->timestamp('valid_until');
            $table->boolean('is_active')->default(true);
            $table->foreignUuid('created_by')->constrained('users');
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('coupons'); }
};
