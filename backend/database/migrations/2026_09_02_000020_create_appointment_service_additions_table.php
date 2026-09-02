<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('appointment_service_additions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('appointment_id')->constrained('appointments')->onDelete('cascade');
            $table->foreignUuid('service_id')->constrained('services');
            $table->foreignUuid('provider_id')->constrained('service_providers');
            $table->foreignUuid('added_by')->constrained('users');
            $table->decimal('price_at_addition', 12, 2);
            $table->integer('duration_minutes_at_addition');
            $table->decimal('commission_percentage_snapshot', 5, 2)->default(0.00);
            $table->decimal('commission_amount', 12, 2)->default(0.00);
            $table->string('status', 20)->default('active');
            $table->timestamp('added_at')->useCurrent();
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('appointment_service_additions'); }
};
