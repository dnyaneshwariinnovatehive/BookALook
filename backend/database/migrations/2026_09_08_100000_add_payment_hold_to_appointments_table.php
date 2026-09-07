<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * How long a slot is held while the customer is on the payment sheet.
 *
 * A booking is created as `pending_payment` before the customer pays, which
 * reserves the slot so nobody else takes it mid-checkout. Without an expiry an
 * abandoned checkout would hold that slot forever.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('appointments', function (Blueprint $table) {
            $table->timestamp('payment_hold_expires_at')->nullable()->after('payment_mode');
        });
    }

    public function down(): void
    {
        Schema::table('appointments', function (Blueprint $table) {
            $table->dropColumn('payment_hold_expires_at');
        });
    }
};
