<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('coupon_redemptions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('coupon_id')->constrained('coupons')->onDelete('cascade');
            $table->foreignUuid('customer_id')->constrained('users');
            $table->foreignUuid('appointment_id')->constrained('appointments');
            $table->decimal('discount_amount', 12, 2);
            $table->string('status', 20)->default('applied'); // applied, reversed
            $table->timestamp('redeemed_at')->useCurrent();
            $table->timestamp('reversed_at')->nullable();
            $table->timestamps();
            
            $table->unique(['coupon_id', 'customer_id', 'appointment_id']);
        });
    }
    public function down(): void { Schema::dropIfExists('coupon_redemptions'); }
};
