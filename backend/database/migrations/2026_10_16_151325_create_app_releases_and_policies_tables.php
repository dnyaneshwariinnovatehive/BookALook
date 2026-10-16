<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('app_releases', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('app', 32); // 'customer' or 'partner'
            $table->string('version', 50); // e.g. "2.4.0"
            $table->unsignedInteger('build_number'); // e.g. 42
            $table->timestamp('released_at')->nullable();
            $table->text('release_notes')->nullable();
            $table->string('android_store_url', 500)->nullable();
            $table->string('ios_store_url', 500)->nullable();
            $table->enum('status', ['draft', 'published', 'retired'])->default('draft');
            $table->foreignUuid('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignUuid('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['app', 'version', 'build_number']);
            $table->index(['app', 'status']);
        });

        Schema::create('app_update_policies', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('app', 32)->unique(); // 'customer' or 'partner'
            $table->foreignUuid('latest_release_id')->nullable()->constrained('app_releases')->nullOnDelete();
            $table->foreignUuid('minimum_release_id')->nullable()->constrained('app_releases')->nullOnDelete();
            $table->enum('update_mode', ['optional', 'mandatory'])->default('optional');
            $table->boolean('is_enforced')->default(false);
            $table->timestamp('enforce_at')->nullable();
            $table->text('update_message')->nullable();
            $table->string('android_store_url', 500)->nullable();
            $table->string('ios_store_url', 500)->nullable();
            $table->foreignUuid('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('app_update_policies');
        Schema::dropIfExists('app_releases');
    }
};
