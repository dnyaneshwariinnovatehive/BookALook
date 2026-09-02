<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('wallet_transactions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('salon_id')->constrained('salons')->onDelete('cascade');
            $table->string('type', 20); // earned, redeemed, adjustment, expired
            $table->integer('coins');
            $table->integer('balance_after');
            $table->decimal('coin_value_snapshot', 12, 2)->nullable();
            $table->foreignUuid('related_scheme_tier_id')->nullable()->constrained('wallet_scheme_tiers');
            $table->foreignUuid('related_appointment_id')->nullable()->constrained('appointments');
            $table->foreignUuid('related_payout_id')->nullable()->constrained('salon_payouts');
            $table->foreignUuid('related_subscription_id')->nullable()->constrained('salon_subscriptions');
            $table->foreignUuid('created_by')->nullable()->constrained('users');
            $table->string('note', 255)->nullable();
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('wallet_transactions'); }
};
