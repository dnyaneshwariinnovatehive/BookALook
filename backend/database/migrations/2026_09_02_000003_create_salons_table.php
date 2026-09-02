<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('salons', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('admin_id')->constrained('users')->onDelete('cascade');
            $table->string('name', 150);
            $table->string('slug', 180)->unique();
            $table->text('description')->nullable();
            $table->string('cover_photo_url', 500)->nullable();
            $table->string('city', 100)->index();
            $table->text('address');
            $table->string('pincode', 10)->nullable();
            $table->string('phone_num', 20)->nullable();
            $table->string('map_url', 500)->nullable();
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->string('status', 30)->default('pending_approval')->index();
            $table->foreignUuid('submitted_by')->constrained('users');
            $table->foreignUuid('approved_by')->nullable()->constrained('users');
            $table->timestamp('approved_at')->nullable();
            $table->text('rejection_reason')->nullable();
            $table->string('qr_code_url', 500)->nullable();
            $table->foreignUuid('assigned_collaborator_id')->nullable()->constrained('users')->index();
            $table->boolean('advance_required')->default(true);
            $table->boolean('advance_refundable')->default(false);
            $table->decimal('advance_percentage_default', 5, 2)->default(25.00);
            $table->decimal('avg_rating', 3, 2)->default(0.00);
            $table->integer('review_count')->default(0);
            $table->text('suspended_reason')->nullable();
            $table->enum('gender_focus', ['Unisex', 'Men Only', 'Women Only'])->default('Unisex');
            $table->timestamps();
            $table->softDeletes();
            
            $table->index(['latitude', 'longitude']);
        });
    }
    public function down(): void { Schema::dropIfExists('salons'); }
};
