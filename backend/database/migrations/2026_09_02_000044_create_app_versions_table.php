<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('app_versions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->enum('app_type', ['customer_app', 'partner_app']);
            $table->enum('platform', ['android', 'ios']);
            $table->string('latest_version', 20);
            $table->string('minimum_supported_version', 20);
            $table->boolean('force_update')->default(false);
            $table->text('release_notes')->nullable();
            $table->string('store_url', 255)->nullable();
            $table->timestamp('released_at')->useCurrent();
            
            $table->unique(['app_type', 'platform']);
        });
    }
    public function down(): void { Schema::dropIfExists('app_versions'); }
};
