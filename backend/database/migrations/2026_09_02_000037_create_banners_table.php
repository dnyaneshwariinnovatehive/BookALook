<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('banners', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('title', 150);
            $table->string('image_url', 255);
            $table->enum('target_scope', ['platform', 'city', 'salon'])->default('platform');
            $table->string('target_city', 100)->nullable();
            $table->foreignUuid('target_salon_id')->nullable()->constrained('salons');
            $table->date('start_date');
            $table->date('end_date');
            $table->boolean('is_active')->default(true);
        });
    }
    public function down(): void { Schema::dropIfExists('banners'); }
};
