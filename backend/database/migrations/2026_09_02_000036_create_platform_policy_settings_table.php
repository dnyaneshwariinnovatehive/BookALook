<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('platform_policy_settings', function (Blueprint $table) {
            $table->string('setting_key', 100)->primary();
            $table->string('setting_value', 255);
            $table->enum('data_type', ['integer', 'decimal', 'boolean', 'string']);
            $table->text('description')->nullable();
            $table->foreignUuid('updated_by')->constrained('users');
        });
    }
    public function down(): void { Schema::dropIfExists('platform_policy_settings'); }
};
