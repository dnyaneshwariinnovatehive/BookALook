<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Banners: separate media axis from content axis.
 *
 * `media_kind` describes WHAT the image_url asset is:
 *   - 'image'    → static raster (jpg/jpeg/png)
 *   - 'animated' → animated raster (gif/webp)
 *
 * It does NOT change banner_type semantics. Defaulting to 'image' means every
 * existing row keeps its current meaning with no data migration.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('banners', function (Blueprint $table) {
            $table->string('media_kind', 16)->default('image')->after('image_url');
        });
    }

    public function down(): void
    {
        Schema::table('banners', function (Blueprint $table) {
            $table->dropColumn('media_kind');
        });
    }
};
