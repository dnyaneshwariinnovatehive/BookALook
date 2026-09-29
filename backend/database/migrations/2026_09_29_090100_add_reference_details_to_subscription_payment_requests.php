<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The reference the owner typed when they uploaded their transfer screenshot.
 *
 * Both optional on purpose. Plenty of owners pay by card or by cash at a branch
 * and have no UTR to quote, and a note is a courtesy rather than a requirement —
 * so neither can be made NOT NULL, and the SuperAdmin review screen has to
 * survive both being absent.
 *
 * 150 characters for the transaction id, matching `payments.gateway_transaction_id`
 * and `salon_payouts.distribution_reference`, so a reference copied from one of
 * those fits without being silently cut.
 */
return new class extends Migration {
    public function up(): void {
        Schema::table('subscription_payment_requests', function (Blueprint $table) {
            $table->string('transaction_id', 150)->nullable()->after('screenshot_url');
            $table->text('note')->nullable()->after('transaction_id');
        });
    }
    public function down(): void {
        Schema::table('subscription_payment_requests', function (Blueprint $table) {
            $table->dropColumn(['transaction_id', 'note']);
        });
    }
};
