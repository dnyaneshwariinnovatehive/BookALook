<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('salon_closures', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('salon_id')->constrained('salons')->onDelete('cascade');
            $table->date('closed_date');
            $table->string('reason', 255)->nullable();
            $table->boolean('triggers_mass_reschedule')->default(false);
            $table->boolean('reschedule_processed')->default(false);
            $table->foreignUuid('processed_by')->nullable()->constrained('users');
            $table->timestamp('processed_at')->nullable();
            $table->foreignUuid('created_by')->constrained('users');
            $table->timestamps();
            
            $table->unique(['salon_id', 'closed_date']);
        });
    }
    public function down(): void { Schema::dropIfExists('salon_closures'); }
};
