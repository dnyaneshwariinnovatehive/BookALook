<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Links an appointment to the emergency closure that took its day away.
 *
 * This is what separates "the customer changed their mind" from "the salon
 * cancelled on them": it drives the free reschedule, the full refund if they
 * walk away instead, and it keeps the change off their same-day abuse counter.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('appointments', function (Blueprint $table) {
            $table->foreignUuid('salon_closure_id')
                ->nullable()
                ->after('reschedule_reason')
                ->constrained('salon_closures')
                ->nullOnDelete();

            $table->timestamp('closure_notified_at')->nullable()->after('salon_closure_id');
        });
    }

    public function down(): void
    {
        Schema::table('appointments', function (Blueprint $table) {
            $table->dropConstrainedForeignId('salon_closure_id');
            $table->dropColumn('closure_notified_at');
        });
    }
};
