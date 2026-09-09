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
        Schema::create('favourite_salons', function (Blueprint $table) {
            $table->id();
            $table->foreignUuid('customer_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUuid('salon_id')->constrained('salons')->cascadeOnDelete();
            $table->timestamps();

            // A customer can only favorite a specific salon once
            $table->unique(['customer_id', 'salon_id']);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('favourite_salons');
    }
};
