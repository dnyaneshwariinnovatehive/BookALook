<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('cart_items', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('cart_id')->constrained('carts')->onDelete('cascade');
            $table->foreignUuid('service_id')->nullable()->constrained('services')->onDelete('cascade');
            $table->foreignUuid('combo_id')->nullable()->constrained('combos')->onDelete('cascade');
            $table->foreignUuid('preferred_provider_id')->nullable()->constrained('service_providers');
            $table->boolean('is_any_available')->default(false);
            $table->integer('quantity')->default(1);
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('cart_items'); }
};
