<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('provider_working_hours', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('provider_id')->constrained('service_providers')->onDelete('cascade');
            $table->smallInteger('day_of_week');
            $table->boolean('is_weekly_off')->default(false);
            $table->time('shift_start')->nullable();
            $table->time('shift_end')->nullable();
            $table->time('break_start')->nullable();
            $table->time('break_end')->nullable();
            
            $table->unique(['provider_id', 'day_of_week']);
        });
    }
    public function down(): void { Schema::dropIfExists('provider_working_hours'); }
};
