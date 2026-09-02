<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('payment_allocations', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('payment_id')->constrained('payments')->onDelete('cascade');
            $table->foreignUuid('appointment_id')->constrained('appointments');
            $table->decimal('allocated_amount', 12, 2);
            $table->string('allocation_type', 30)->default('booking'); // booking, reschedule_carry_forward, adjustment
            $table->foreignUuid('created_by')->nullable()->constrained('users');
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('payment_allocations'); }
};
