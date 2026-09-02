<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('combo_services', function (Blueprint $table) {
            $table->foreignUuid('combo_id')->constrained('combos')->onDelete('cascade');
            $table->foreignUuid('service_id')->constrained('services')->onDelete('cascade');
            $table->decimal('combo_special_price', 10, 2);
            
            $table->primary(['combo_id', 'service_id']);
        });
    }
    public function down(): void { Schema::dropIfExists('combo_services'); }
};
