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
        Schema::create('notification_templates', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('key', 100)->unique(); // e.g. booking_created_customer
            $table->string('type', 50); // Maps back to NotificationType (e.g. booking_created)
            $table->string('audience', 50); // 'customer' or 'partner'
            $table->boolean('is_enabled')->default(true);
            $table->string('default_title', 255);
            $table->text('default_message');
            $table->string('title', 255)->nullable();
            $table->text('message')->nullable();
            $table->jsonb('available_variables')->nullable();
            $table->jsonb('channels')->nullable();
            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('notification_templates');
    }
};
