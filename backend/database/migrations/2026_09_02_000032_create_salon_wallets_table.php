<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('salon_wallets', function (Blueprint $table) {
            $table->foreignUuid('salon_id')->primary()->constrained('salons')->onDelete('cascade');
            $table->integer('coin_balance')->default(0);
            $table->integer('completed_online_appointments_count')->default(0);
        });
    }
    public function down(): void { Schema::dropIfExists('salon_wallets'); }
};
