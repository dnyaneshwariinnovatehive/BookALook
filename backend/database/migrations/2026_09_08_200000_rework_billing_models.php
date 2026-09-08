<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Splits the two ways a salon pays to trade, and names them the same way
 * everywhere.
 *
 * A salon is either on a Subscription Plan (prepaid, expires, must be renewed)
 * or on the Commission Model (postpaid, a percentage of what it billed, settled
 * monthly). The old vocabulary called the first one "flat", which meant nothing
 * to anyone reading it, so the stored value now says what it is.
 *
 * Three things move as a result:
 *
 *  - The commission rate belongs to the salon, not to a subscription row that
 *    gets replaced on every renewal. It was being lost on renewal.
 *  - Rate changes are kept as history, because a payout must be able to explain
 *    which rate it charged and why.
 *  - Payout cycles are weekly for subscription salons and monthly for
 *    commission ones, so the columns can no longer be named after a week.
 */
return new class extends Migration
{
    public function up(): void
    {
        // ---------------------------------------------------------- vocabulary
        foreach (['salon_subscriptions', 'salon_payouts', 'subscription_payment_requests'] as $table) {
            DB::table($table)->where('billing_type', 'flat')->update(['billing_type' => 'subscription']);
        }

        // ------------------------------------------------- the commission plan
        // Every salon on the Commission Model enjoys the same benefits, so one
        // plan is nominated to carry them rather than each salon being pointed
        // at a plan by hand.
        Schema::table('subscription_plans', function (Blueprint $table) {
            $table->boolean('is_commission_plan')->default(false)->after('is_active');
        });

        // ------------------------------------------------------- the rate
        Schema::table('salons', function (Blueprint $table) {
            $table->decimal('commission_percentage', 5, 2)->nullable()->after('commission_opt_in');
            $table->date('commission_rate_effective_from')->nullable()->after('commission_percentage');
        });

        // Rates already agreed with a salon live on its active subscription.
        // Lift them onto the salon so a renewal cannot drop them.
        $live = DB::table('salon_subscriptions')
            ->where('billing_type', 'commission')
            ->where('status', 'active')
            ->whereNotNull('commission_percentage')
            ->get(['salon_id', 'commission_percentage', 'start_date']);

        foreach ($live as $subscription) {
            DB::table('salons')->where('id', $subscription->salon_id)->update([
                'commission_opt_in' => true,
                'commission_percentage' => $subscription->commission_percentage,
                'commission_rate_effective_from' => $subscription->start_date,
            ]);
        }

        // --------------------------------------------------- rate history
        Schema::create('salon_commission_rates', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('salon_id')->constrained('salons')->onDelete('cascade');
            $table->decimal('percentage', 5, 2);
            $table->date('effective_from');
            // Left open until a newer rate supersedes this one.
            $table->date('effective_to')->nullable();
            $table->foreignUuid('set_by')->nullable()->constrained('users');
            $table->string('reason', 255)->nullable();
            $table->timestamps();

            $table->index(['salon_id', 'effective_from']);
        });

        foreach ($live as $subscription) {
            DB::table('salon_commission_rates')->insert([
                'id' => (string) Str::uuid(),
                'salon_id' => $subscription->salon_id,
                'percentage' => $subscription->commission_percentage,
                'effective_from' => $subscription->start_date,
                'effective_to' => null,
                'set_by' => null,
                'reason' => 'Carried over from the salon’s existing arrangement.',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        // ------------------------------------------------------ payout cycles
        Schema::table('salon_payouts', function (Blueprint $table) {
            $table->renameColumn('cycle_week_start_date', 'cycle_start_date');
            $table->renameColumn('cycle_week_end_date', 'cycle_end_date');
        });

        Schema::table('salon_payouts', function (Blueprint $table) {
            $table->string('cycle_type', 10)->default('weekly')->after('salon_id');
        });

        DB::table('salon_payouts')
            ->where('billing_type', 'commission')
            ->update(['cycle_type' => 'monthly']);

        // ------------------------------------------- postpaid has no receipt
        // A Commission Model request is not a payment, so it arrives without a
        // screenshot to verify.
        Schema::table('subscription_payment_requests', function (Blueprint $table) {
            $table->string('screenshot_url')->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('subscription_payment_requests', function (Blueprint $table) {
            $table->string('screenshot_url')->nullable(false)->change();
        });

        Schema::table('salon_payouts', function (Blueprint $table) {
            $table->dropColumn('cycle_type');
        });

        Schema::table('salon_payouts', function (Blueprint $table) {
            $table->renameColumn('cycle_start_date', 'cycle_week_start_date');
            $table->renameColumn('cycle_end_date', 'cycle_week_end_date');
        });

        Schema::dropIfExists('salon_commission_rates');

        Schema::table('salons', function (Blueprint $table) {
            $table->dropColumn(['commission_percentage', 'commission_rate_effective_from']);
        });

        Schema::table('subscription_plans', function (Blueprint $table) {
            $table->dropColumn('is_commission_plan');
        });

        foreach (['salon_subscriptions', 'salon_payouts', 'subscription_payment_requests'] as $table) {
            DB::table($table)->where('billing_type', 'subscription')->update(['billing_type' => 'flat']);
        }
    }
};
