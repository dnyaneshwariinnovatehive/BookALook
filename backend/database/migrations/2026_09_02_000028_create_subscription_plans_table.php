<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('subscription_plans', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('name', 50);
            $table->decimal('price', 12, 2)->default(0.00);
            $table->integer('whatsapp_campaign_limit')->default(0);
            $table->boolean('has_customer_segmentation')->default(false);
            $table->boolean('has_service_based_targeting')->default(false);
            $table->boolean('has_high_value_targeting')->default(false);
            $table->boolean('has_advanced_insights')->default(false);
            $table->string('has_upsell_recommendations', 20)->default('none');
            $table->string('has_cross_sell_recommendations', 20)->default('none');
            $table->boolean('has_priority_visibility')->default(false);
            $table->boolean('is_active')->default(true);
            $table->foreignUuid('created_by')->nullable()->constrained('users');
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('subscription_plans'); }
};
