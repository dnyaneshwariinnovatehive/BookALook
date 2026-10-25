<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The add-ons a salon owner recommends alongside a service: "with a Haircut,
 * suggest Hair Spa". Both sides are the same salon's own services, and the
 * link dies with either of them.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('service_upsells', function (Blueprint $table) {
            $table->foreignUuid('service_id')->constrained('services')->cascadeOnDelete();
            $table->foreignUuid('upsell_service_id')->constrained('services')->cascadeOnDelete();
            $table->unsignedSmallInteger('display_order')->default(0);
            $table->timestamps();

            $table->primary(['service_id', 'upsell_service_id']);
            $table->index('upsell_service_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('service_upsells');
    }
};
