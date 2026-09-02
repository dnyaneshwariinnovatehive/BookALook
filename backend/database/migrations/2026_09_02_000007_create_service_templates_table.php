<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('service_templates', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('category_id')->constrained('service_categories')->onDelete('cascade');
            $table->string('name', 150);
            $table->integer('estimated_duration_minutes')->default(30);
            $table->boolean('is_custom')->default(false);
            $table->foreignUuid('created_by_salon_id')->nullable()->constrained('salons')->onDelete('cascade');
            $table->timestamp('promoted_to_standard_at')->nullable();
            $table->foreignUuid('promoted_by')->nullable()->constrained('users');
            $table->boolean('is_active')->default(true);
        });
    }
    public function down(): void { Schema::dropIfExists('service_templates'); }
};
