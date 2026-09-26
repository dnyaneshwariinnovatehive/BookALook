<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    /**
     * The outbox for every outbound notification, and the only place that can
     * answer "did this reach the phone, or did we merely write a row and hope".
     *
     * `channel` and `status` are strings, not enums, for the same reason
     * whatsapp_messages.status is one: the vocabulary is enforced in the model
     * constants where it can be read and changed in one place, and the column
     * stays open to the next channel without a migration. The delivery ledger
     * outlives any single provider, so nothing here names FCM.
     */
    public function up(): void
    {
        Schema::create('notification_deliveries', function (Blueprint $table) {
            $table->uuid('id')->primary();

            $table->foreignUuid('notification_id')->constrained('notifications')->cascadeOnDelete();
            $table->foreignUuid('user_device_id')->constrained('user_devices')->cascadeOnDelete();

            // 'push' today; 'sms', 'email' and the rest later.
            $table->string('channel', 30);

            // 'pending', 'sent', 'failed' — see NotificationDelivery.
            $table->string('status', 20)->default('pending');

            // 'log' until a real driver ships; then 'fcm'.
            $table->string('provider', 40);

            // A masked snapshot of where the send was aimed. A push token is a
            // bearer credential, and user_devices already holds the live one, so
            // the ledger keeps a recognisable reference rather than a second
            // plaintext copy of a secret.
            $table->string('destination', 255);

            $table->string('provider_message_id', 255)->nullable();
            $table->unsignedTinyInteger('attempt_count')->default(0);
            $table->text('failure_reason')->nullable();
            $table->timestamp('sent_at')->nullable();
            $table->timestamp('delivered_at')->nullable();
            $table->timestamp('failed_at')->nullable();
            $table->timestamps();

            $table->index('notification_id');
            $table->index('user_device_id');

            // Retries and failure triage both ask "what is still outstanding,
            // oldest first", so status leads and created_at sorts.
            $table->index(['status', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('notification_deliveries');
    }
};
