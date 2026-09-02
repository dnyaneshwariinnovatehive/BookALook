<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('service_categories', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('name', 80);
            $table->string('icon_url', 255)->nullable();
            $table->boolean('is_custom')->default(false);
            $table->foreignUuid('created_by_salon_id')->nullable()->constrained('salons')->onDelete('cascade');
            $table->timestamp('promoted_to_standard_at')->nullable();
            $table->foreignUuid('promoted_by')->nullable()->constrained('users');
            $table->boolean('is_active')->default(true);
            $table->integer('display_order')->default(0);
        });
    }
    public function down(): void { Schema::dropIfExists('service_categories'); }
};
