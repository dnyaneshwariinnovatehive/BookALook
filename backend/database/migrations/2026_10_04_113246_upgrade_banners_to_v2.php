<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Banners v2: rule-based dynamic banners.
 *
 * Existing banners become type 'static' and keep working exactly as before.
 * New types (combo_discount, specific_combo, new_arrivals, category_spotlight,
 * seasonal) store their parameters in a JSON `config` column, and the customer
 * API resolves them at query time.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('banners', function (Blueprint $table) {
            $table->string('banner_type', 30)->default('static')->after('title');

            // Type-specific parameters. Examples:
            //   combo_discount:     {"min_discount_pct": 30, "auto_hide": true}
            //   specific_combo:     {"service_template_ids": ["uuid1","uuid2"]}
            //   new_arrivals:       {"window_days": 7, "auto_hide": true}
            //   category_spotlight: {"category_id": "uuid"}
            //   seasonal:           {"theme": "diwali"}
            $table->json('config')->nullable()->after('banner_type');

            // Sub-area targeting — finer than city.
            $table->foreignUuid('target_sub_area_id')->nullable()->after('target_salon_id')
                  ->constrained('sub_areas')->nullOnDelete();

            // Display priority — lower number = shown first.
            $table->unsignedInteger('priority')->default(0)->after('is_active');

            // Analytics counters.
            $table->unsignedBigInteger('impressions')->default(0)->after('priority');
            $table->unsignedBigInteger('clicks')->default(0)->after('impressions');

            $table->timestamps();

            $table->index(['banner_type', 'is_active']);
        });
    }

    public function down(): void
    {
        Schema::table('banners', function (Blueprint $table) {
            $table->dropConstrainedForeignId('target_sub_area_id');
            $table->dropColumn([
                'banner_type', 'config', 'priority',
                'impressions', 'clicks',
                'created_at', 'updated_at',
            ]);
        });
    }
};
