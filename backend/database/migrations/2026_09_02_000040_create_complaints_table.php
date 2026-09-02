<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('complaints', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('salon_id')->constrained('salons')->onDelete('cascade');
            $table->foreignUuid('customer_id')->constrained('users');
            $table->foreignUuid('related_appointment_id')->nullable()->constrained('appointments');
            $table->string('subject', 150);
            $table->text('description');
            $table->enum('status', ['open', 'under_review', 'resolved', 'dismissed'])->default('open');
            $table->foreignUuid('resolved_by')->nullable()->constrained('users');
            $table->timestamp('resolved_at')->nullable();
        });
    }
    public function down(): void { Schema::dropIfExists('complaints'); }
};
