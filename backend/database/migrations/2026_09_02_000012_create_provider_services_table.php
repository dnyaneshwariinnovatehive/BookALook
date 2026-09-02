<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('provider_services', function (Blueprint $table) {
            $table->foreignUuid('provider_id')->constrained('service_providers')->onDelete('cascade');
            $table->foreignUuid('service_id')->constrained('services')->onDelete('cascade');
            $table->primary(['provider_id', 'service_id']);
        });
    }
    public function down(): void { Schema::dropIfExists('provider_services'); }
};
