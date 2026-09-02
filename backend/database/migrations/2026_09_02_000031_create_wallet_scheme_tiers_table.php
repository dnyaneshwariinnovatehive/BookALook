<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('wallet_scheme_tiers', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('scheme_id')->constrained('wallet_schemes')->onDelete('cascade');
            $table->integer('tier_order');
            $table->integer('appointments_required');
            $table->integer('coins_awarded');
            
            $table->unique(['scheme_id', 'tier_order']);
        });
    }
    public function down(): void { Schema::dropIfExists('wallet_scheme_tiers'); }
};
