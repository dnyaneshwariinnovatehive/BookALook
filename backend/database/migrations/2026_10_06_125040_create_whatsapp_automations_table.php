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
        Schema::create('whatsapp_automations', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('key', 60)->unique();
            $table->string('name', 120);
            $table->text('description')->nullable();
            $table->string('audience', 60);
            $table->string('frequency_label', 120)->nullable();
            $table->boolean('is_enabled')->default(false);
            $table->string('aisensy_campaign_name', 120)->nullable();
            $table->integer('lead_time_minutes')->nullable();
            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('whatsapp_automations');
    }
};
