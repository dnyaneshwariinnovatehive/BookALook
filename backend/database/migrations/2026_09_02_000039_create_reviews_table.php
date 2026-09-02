<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('reviews', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('appointment_id')->unique()->constrained('appointments');
            $table->foreignUuid('customer_id')->constrained('users');
            $table->foreignUuid('salon_id')->constrained('salons')->onDelete('cascade');
            $table->smallInteger('rating');
            $table->text('comment')->nullable();
        });
    }
    public function down(): void { Schema::dropIfExists('reviews'); }
};
