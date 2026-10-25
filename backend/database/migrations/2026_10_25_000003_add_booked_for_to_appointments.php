<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Who an online booking is actually for.
 *
 * The account holder pays and owns the booking; the recipient is the person
 * who sits in the chair. Every booking made before this is for the account
 * holder, which is exactly what a null recipient means.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('appointments', function (Blueprint $table) {
            $table->string('booked_for', 10)->default('self');
            $table->string('recipient_name', 150)->nullable();
            $table->string('recipient_gender', 10)->nullable();
            $table->string('recipient_phone', 15)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('appointments', function (Blueprint $table) {
            $table->dropColumn(['booked_for', 'recipient_name', 'recipient_gender', 'recipient_phone']);
        });
    }
};
