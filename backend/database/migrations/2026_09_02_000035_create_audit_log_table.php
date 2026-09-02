<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('audit_log', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('actor_id')->constrained('users');
            $table->string('action', 150);
            $table->string('entity_type', 100);
            $table->uuid('entity_id')->nullable();
            $table->string('field_name', 100)->nullable();
            $table->jsonb('old_value')->nullable();
            $table->jsonb('new_value')->nullable();
            $table->jsonb('metadata')->nullable();
            // Since sqlite doesn't support inet natively we use string
            $table->string('ip_address', 45)->nullable(); 
            $table->text('user_agent')->nullable();
            $table->string('request_id', 100)->nullable();
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('audit_log'); }
};
