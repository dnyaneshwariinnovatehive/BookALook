<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Gives a customer a city, so the app can show them salons they can reach.
 *
 * The platform already knew which city every salon was in; it had no idea
 * which city the customer was in, so the directory showed everything
 * everywhere. A customer in Pune scrolling past salons in Bangalore is not
 * browsing a marketplace, they are browsing a database.
 *
 * Nullable on purpose. Customers browse as guests before they ever sign in,
 * and the app holds the choice locally until there is an account to hang it
 * on — so an empty column here means "not chosen yet", not "broken".
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->foreignUuid('city_id')->nullable()->after('pincode')->constrained('cities');
            $table->index('city_id');
        });

        // The directory filters on exactly this pair on every request, and
        // there was no index covering it.
        Schema::table('salons', function (Blueprint $table) {
            $table->index(['city_id', 'status'], 'salons_city_status_index');
        });
    }

    public function down(): void
    {
        Schema::table('salons', function (Blueprint $table) {
            $table->dropIndex('salons_city_status_index');
        });

        Schema::table('users', function (Blueprint $table) {
            $table->dropConstrainedForeignId('city_id');
        });
    }
};
