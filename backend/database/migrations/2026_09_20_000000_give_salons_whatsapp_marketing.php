<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * WhatsApp marketing: the campaign machinery.
 *
 * The subscription side of this already existed — every entitlement column the
 * plan spec asks for is on `subscription_plans` and SuperAdmin can already edit
 * them. What was missing was anything to entitle: nothing in the codebase read
 * `whatsapp_campaign_limit`, so the quota was decorative.
 *
 * Four new tables and three sets of columns close that gap:
 *
 *  - `campaign_templates` is the platform's curated catalogue. Meta approves
 *    templates, not messages, so a salon can never write free text — it picks
 *    an approved template and fills the blanks. That constraint comes from
 *    WhatsApp, and it happens to be exactly the "ready-made templates" the
 *    spec describes.
 *  - `campaigns` is one salon's send, including which billing cycle it was
 *    charged to. Counters reset with the subscription, not the calendar, so
 *    the cycle has to be recorded at send time rather than inferred later.
 *  - `campaign_recipients` is the per-person row. Without it there is no
 *    "advanced campaign analytics", only a total.
 *  - `marketing_consents` is keyed on phone rather than user, because a walk-in
 *    customer has a phone number and no account, and the right to be left alone
 *    belongs to the number.
 */
return new class extends Migration
{
    public function up(): void
    {
        // The catalogue. Platform-owned: one WhatsApp Business account sends for
        // every salon, so one approved template set serves all of them.
        Schema::create('campaign_templates', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('key')->unique();
            $table->string('name');
            $table->string('category');
            $table->text('description')->nullable();

            // What this is registered as on the WhatsApp Business account. Null
            // until the template clears Meta review, which is what `is_active`
            // is really gating.
            $table->string('meta_template_name')->nullable();
            $table->string('language', 10)->default('en');

            // The copy with {{1}}-style placeholders, kept so the partner app
            // can show what will actually arrive without calling Meta.
            $table->text('body_preview');
            $table->json('variables')->nullable();
            $table->json('default_audience')->nullable();

            // Growth-only templates exist because some campaigns are only
            // meaningful with targeting behind them.
            $table->string('min_plan')->default('starter');

            $table->boolean('is_active')->default(false);
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();

            $table->index(['is_active', 'category']);
        });

        Schema::create('campaigns', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('salon_id')->constrained('salons')->cascadeOnDelete();
            $table->foreignUuid('campaign_template_id')->constrained('campaign_templates');
            $table->foreignUuid('created_by')->nullable()->constrained('users')->nullOnDelete();

            $table->string('name');
            $table->string('status')->default('draft');

            // The filter that produced the audience, kept verbatim. A recount
            // months later would give a different answer — customers keep
            // booking — so the question "who did this go to" is answered by
            // campaign_recipients, and this records only what was asked for.
            $table->json('audience')->nullable();
            $table->json('variables')->nullable();

            $table->dateTime('scheduled_for')->nullable();

            $table->unsignedInteger('recipients_count')->default(0);
            $table->unsignedInteger('sent_count')->default(0);
            $table->unsignedInteger('delivered_count')->default(0);
            $table->unsignedInteger('read_count')->default(0);
            $table->unsignedInteger('failed_count')->default(0);
            $table->unsignedInteger('skipped_count')->default(0);

            // Which subscription period this was billed against. Recorded rather
            // than derived: a salon that renews mid-month must not have last
            // cycle's sends counted against the new one.
            $table->date('cycle_start')->nullable();
            $table->date('cycle_end')->nullable();

            $table->dateTime('started_at')->nullable();
            $table->dateTime('completed_at')->nullable();
            $table->text('failure_reason')->nullable();
            $table->timestamps();

            $table->index(['salon_id', 'status']);
            $table->index(['salon_id', 'cycle_start']);
            $table->index('scheduled_for');
        });

        Schema::create('campaign_recipients', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('campaign_id')->constrained('campaigns')->cascadeOnDelete();

            // Nullable throughout: a walk-in customer is a name and a number on
            // an appointment, with no account behind it.
            $table->foreignUuid('user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('phone');
            $table->string('name')->nullable();

            $table->json('variables')->nullable();
            $table->uuid('whatsapp_message_id')->nullable();

            $table->string('status')->default('pending');
            $table->string('skip_reason')->nullable();
            $table->timestamps();

            // One message per person per campaign. A customer who appears in
            // two segments of the same send should still hear from the salon
            // once.
            $table->unique(['campaign_id', 'phone']);
            $table->index(['campaign_id', 'status']);
        });

        Schema::create('marketing_consents', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('phone')->unique();
            $table->foreignUuid('user_id')->nullable()->constrained('users')->nullOnDelete();

            $table->string('status')->default('opted_in');
            $table->string('source')->default('booking');

            $table->dateTime('opted_in_at')->nullable();
            $table->dateTime('opted_out_at')->nullable();
            $table->timestamps();

            $table->index('status');
        });

        // The outbox learns what a campaign is, and learns to record what
        // happened after "sent" — delivery and read receipts are the whole of
        // campaign analytics.
        Schema::table('whatsapp_messages', function (Blueprint $table) {
            $table->foreignUuid('campaign_id')->nullable()->after('related_salon_id')
                ->constrained('campaigns')->nullOnDelete();

            // Meta prices and polices marketing differently from utility, and a
            // booking reminder must never be counted against a marketing quota.
            $table->string('category')->default('utility')->after('template');

            $table->dateTime('delivered_at')->nullable()->after('sent_at');
            $table->dateTime('read_at')->nullable()->after('delivered_at');
            $table->dateTime('failed_at')->nullable()->after('read_at');
        });

        // A message allowance alongside the campaign allowance. Which of the two
        // actually binds is left to whoever sets the numbers: zero means "do not
        // count this one", so a plan can be capped by campaigns, by messages, by
        // both, or by neither without a schema change.
        Schema::table('subscription_plans', function (Blueprint $table) {
            $table->unsignedInteger('whatsapp_message_limit')->default(0)
                ->after('whatsapp_campaign_limit');
        });

        $this->seedPolicyDefaults();
    }

    /**
     * Platform-wide marketing rules, on the same key/value table the policy
     * page already edits.
     *
     * These are deliberately not per-plan. What counts as an "inactive"
     * customer, and the hours during which a salon may not message anyone, are
     * properties of the platform's conduct rather than of what a salon paid.
     */
    private function seedPolicyDefaults(): void
    {
        $actor = DB::table('users')->where('role', 'superadmin')->value('id');

        // Nothing to attribute the rows to. The settings have working defaults
        // in code, so a fresh database is not broken by skipping this.
        if (! $actor) {
            return;
        }

        $defaults = [
            ['marketing_inactive_customer_days', '60', 'integer',
                'A customer with no completed visit in this many days counts as inactive and can be targeted by reactivation campaigns.'],
            ['marketing_repeat_customer_visits', '3', 'integer',
                'Completed visits before a customer is treated as a repeat customer.'],
            ['marketing_high_value_min_spend', '5000', 'decimal',
                'Lifetime spend, in rupees, at or above which a customer is treated as high value.'],
            ['marketing_quiet_hours_start', '21', 'integer',
                'Hour of day (24h) after which marketing messages are held until morning.'],
            ['marketing_quiet_hours_end', '9', 'integer',
                'Hour of day (24h) before which marketing messages are held.'],
            ['marketing_daily_cap_per_salon', '500', 'integer',
                'Most marketing messages one salon may send in a day, whatever its plan allows for the month. 0 removes the cap.'],
            ['marketing_require_explicit_opt_in', '1', 'boolean',
                'When on, only customers who have opted in receive marketing. When off, any customer with a completed booking is treated as reachable — an opt-out is always honoured either way.'],
        ];

        foreach ($defaults as [$key, $value, $type, $description]) {
            DB::table('platform_policy_settings')->updateOrInsert(
                ['setting_key' => $key],
                [
                    'setting_value' => $value,
                    'data_type' => $type,
                    'description' => $description,
                    'updated_by' => $actor,
                ]
            );
        }
    }

    public function down(): void
    {
        Schema::table('whatsapp_messages', function (Blueprint $table) {
            $table->dropConstrainedForeignId('campaign_id');
            $table->dropColumn(['category', 'delivered_at', 'read_at', 'failed_at']);
        });

        Schema::table('subscription_plans', function (Blueprint $table) {
            $table->dropColumn('whatsapp_message_limit');
        });

        Schema::dropIfExists('campaign_recipients');
        Schema::dropIfExists('campaigns');
        Schema::dropIfExists('campaign_templates');
        Schema::dropIfExists('marketing_consents');

        DB::table('platform_policy_settings')->where('setting_key', 'like', 'marketing_%')->delete();
    }
};
