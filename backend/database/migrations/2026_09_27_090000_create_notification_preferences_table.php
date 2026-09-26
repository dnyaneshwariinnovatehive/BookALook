<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('notification_preferences', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained('users')->onDelete('cascade');

            // A salon owner is very often also a customer, and a collaborator can
            // be handed several. Keying preferences by app means the Customer App
            // toggle cannot quietly silence a salon owner, and the two audiences
            // can genuinely want different things.
            $table->string('app_type', 30);

            // The master switch. When this is off nothing is pushed to that user
            // on that app — the inbox still fills, because the inbox is a
            // record of what happened rather than a channel the user switches off.
            $table->boolean('push_enabled')->default(true);

            // Category switches. Transactional traffic does not consult these;
            // it is only here so a future marketing or reminder setting has
            // somewhere to live without another migration.
            $table->boolean('booking_notifications')->default(true);
            $table->boolean('appointment_reminders')->default(true);
            $table->boolean('payment_notifications')->default(true);
            $table->boolean('promotional_notifications')->default(true);

            $table->timestamps();

            $table->unique(['user_id', 'app_type']);
            $table->index(['app_type', 'push_enabled']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('notification_preferences');
    }
};
