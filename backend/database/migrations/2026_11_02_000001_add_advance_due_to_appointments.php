<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The advance a booking's policy asks for, kept apart from what was paid.
 *
 * `advance_amount` has always meant "advance received" — the bill, refunds,
 * day-close carry-forward and payouts all read it that way. With no online
 * gateway, a booking is confirmed before anything is paid, so the amount
 * still to be collected needs its own column.
 *
 * Additive only: no existing row is changed. Null on older bookings means the
 * advance asked for was the advance paid (BookingPaymentService::summary).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('appointments', function (Blueprint $table) {
            $table->decimal('advance_due', 12, 2)->nullable()->after('advance_amount');
        });
    }

    public function down(): void
    {
        Schema::table('appointments', function (Blueprint $table) {
            $table->dropColumn('advance_due');
        });
    }
};
