<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('notifications', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained('users')->onDelete('cascade');
            $table->string('type', 50);
            $table->string('title', 150);
            $table->text('message');
            $table->jsonb('data')->nullable();
            $table->foreignUuid('related_appointment_id')->nullable()->constrained('appointments');
            $table->foreignUuid('related_salon_id')->nullable()->constrained('salons');
            $table->boolean('is_read')->default(false);
            $table->timestamp('read_at')->nullable();
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('notifications'); }
};
