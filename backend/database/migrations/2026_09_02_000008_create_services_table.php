<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('services', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('salon_id')->constrained('salons')->onDelete('cascade');
            $table->foreignUuid('template_id')->constrained('service_templates');
            $table->text('description')->nullable();
            $table->decimal('price', 12, 2);
            $table->decimal('advance_percentage', 5, 2)->nullable();
            $table->boolean('will_refund_advance_if_cancelled')->default(false);
            $table->boolean('is_active')->default(true);
            $table->integer('display_order')->default(0);
            $table->timestamps();
            $table->softDeletes();
            
            $table->unique(['salon_id', 'template_id']);
        });
    }
    public function down(): void { Schema::dropIfExists('services'); }
};
