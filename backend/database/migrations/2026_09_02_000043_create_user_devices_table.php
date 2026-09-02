<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('user_devices', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained('users')->onDelete('cascade');
            $table->enum('app_type', ['customer_app', 'partner_app']);
            $table->enum('platform', ['android', 'ios']);
            $table->string('push_token', 255)->nullable();
            $table->string('app_version', 20);
            $table->string('device_model', 100)->nullable();
            $table->string('os_version', 20)->nullable();
            $table->timestamp('last_active_at')->useCurrent();
            $table->boolean('is_active')->default(true);
            
            $table->unique(['user_id', 'push_token']);
        });
    }
    public function down(): void { Schema::dropIfExists('user_devices'); }
};
