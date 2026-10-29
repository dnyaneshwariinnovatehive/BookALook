<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A salon owner writing to BookALook from the Partner App — most often from
 * the lock screen, about a settlement — and SuperAdmin's reply.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('salon_support_requests', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('salon_id')->constrained('salons')->cascadeOnDelete();
            $table->foreignUuid('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('topic', 40);
            // The settlement it is about, when it is about one.
            $table->foreignUuid('salon_payout_id')->nullable()->constrained('salon_payouts')->nullOnDelete();
            $table->text('message');
            $table->string('status', 20)->default('open');
            $table->text('reply')->nullable();
            $table->foreignUuid('replied_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('replied_at')->nullable();
            $table->timestamp('resolved_at')->nullable();
            $table->timestamps();

            $table->index(['status', 'created_at']);
            $table->index(['salon_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('salon_support_requests');
    }
};
