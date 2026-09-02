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
        Schema::create('combo_services', function (Blueprint $table) {
                        $table->foreignUuid('combo_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('service_id')->constrained()->cascadeOnDelete();
            $table->decimal('combo_special_price', 10, 2);
            $table->primary(['combo_id', 'service_id']);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('combo_services');
    }
};
