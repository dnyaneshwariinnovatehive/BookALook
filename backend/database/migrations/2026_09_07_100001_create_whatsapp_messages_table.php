<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Outbox for WhatsApp notifications.
 *
 * No provider is wired up yet, so rows sit at status `queued` and the log
 * driver records what would have gone out. When a real gateway is connected it
 * drains this table, which gives delivery history, retries and an audit trail
 * from day one instead of fire-and-forget sends.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('whatsapp_messages', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->nullable()->constrained('users')->nullOnDelete();

            // Snapshotted, because the user may change their number later and
            // we need to know where the message actually went.
            $table->string('to_phone', 20);

            // Meta-approved template name plus the variables it interpolates.
            $table->string('template', 100);
            $table->json('payload')->nullable();

            $table->foreignUuid('related_appointment_id')->nullable()->constrained('appointments')->nullOnDelete();
            $table->foreignUuid('related_salon_id')->nullable()->constrained('salons')->nullOnDelete();

            // queued | sent | failed | skipped
            $table->string('status', 20)->default('queued');
            $table->string('provider', 40)->nullable();
            $table->string('provider_message_id', 100)->nullable();
            $table->text('error')->nullable();
            $table->unsignedTinyInteger('attempts')->default(0);
            $table->timestamp('sent_at')->nullable();
            $table->timestamps();

            $table->index(['status', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('whatsapp_messages');
    }
};
