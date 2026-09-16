<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Remembers the coins a salon put towards a plan it is waiting to have approved.
 *
 * Buying a plan is a two-step affair: the owner transfers what is owed and
 * uploads a receipt, and SuperAdmin turns that into a subscription. Coins have
 * to survive that gap. They cannot be taken when the request is made — a
 * request that is never approved would have burnt them — so the request carries
 * the intent, and the coins actually leave the wallet in the same transaction
 * that creates the subscription.
 *
 * The discount is stored alongside so SuperAdmin can see what the owner was
 * quoted, and so the figure the owner was asked to transfer is reconstructable
 * later even if the coin rate changes.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('subscription_payment_requests', function (Blueprint $table) {
            $table->unsignedInteger('coins_to_redeem')->default(0)->after('billing_type');
            $table->decimal('coin_discount_inr', 12, 2)->default(0)->after('coins_to_redeem');
            // What the owner was actually asked to transfer, after coins.
            $table->decimal('amount_payable_inr', 12, 2)->nullable()->after('coin_discount_inr');
        });
    }

    public function down(): void
    {
        Schema::table('subscription_payment_requests', function (Blueprint $table) {
            $table->dropColumn(['coins_to_redeem', 'coin_discount_inr', 'amount_payable_inr']);
        });
    }
};
