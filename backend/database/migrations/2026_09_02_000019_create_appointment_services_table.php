<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('appointment_services', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('appointment_id')->constrained('appointments')->onDelete('cascade');
            $table->foreignUuid('service_id')->constrained('services');
            $table->foreignUuid('combo_id')->nullable()->constrained('combos');
            $table->foreignUuid('serving_provider_id')->nullable()->constrained('service_providers');
            $table->decimal('price_at_booking', 12, 2);
            $table->decimal('original_service_price', 12, 2);
            $table->integer('duration_minutes_at_booking');
            $table->decimal('commission_percentage_snapshot', 5, 2)->default(0.00);
            $table->decimal('commission_amount', 12, 2)->default(0.00);
            $table->string('line_status', 20)->default('booked');
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('appointment_services'); }
};
