<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('salon_working_hours', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('salon_id')->constrained('salons')->onDelete('cascade');
            $table->smallInteger('day_of_week'); // 0=Sunday ... 6=Saturday
            $table->boolean('is_closed')->default(false);
            $table->time('open_time')->nullable();
            $table->time('close_time')->nullable();
            
            $table->unique(['salon_id', 'day_of_week']);
        });
    }
    public function down(): void { Schema::dropIfExists('salon_working_hours'); }
};
