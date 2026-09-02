<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('salon_subscriptions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('salon_id')->constrained('salons')->onDelete('cascade');
            $table->foreignUuid('plan_id')->constrained('subscription_plans');
            $table->string('feature_level', 20); // starter, growth
            $table->string('billing_type', 20)->default('flat'); // flat, commission
            $table->decimal('commission_percentage', 5, 2)->nullable();
            $table->decimal('plan_price_snapshot', 12, 2)->default(0.00);
            $table->date('start_date');
            $table->date('end_date');
            $table->string('status', 20)->default('active'); // active, expired, cancelled
            $table->boolean('auto_renew')->default(false);
            $table->foreignUuid('renewed_from_id')->nullable()->constrained('salon_subscriptions');
            $table->timestamp('cancelled_at')->nullable();
            $table->foreignUuid('cancelled_by')->nullable()->constrained('users');
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('salon_subscriptions'); }
};
