<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Remembers which enquiry a salon was onboarded from.
 *
 * A collaborator only ever onboards a salon that SuperAdmin assigned to them,
 * and that assignment lives on the enquiry. Without a link back, nothing could
 * answer three questions the flow depends on: has this enquiry already been
 * onboarded (so a retried submit does not create a second salon), which salon
 * does a rejected enquiry refer to (so the collaborator can fix and resubmit),
 * and what did the owner originally ask for (shown beside the salon).
 *
 * Nullable by design: salons that register themselves from the partner app
 * never had an enquiry, and that is not a gap to be filled.
 *
 * No foreign key — SQLite cannot add one to an existing table, and the column
 * is only ever written from the onboarding endpoint, which has the enquiry in
 * hand.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('salons', function (Blueprint $table) {
            $table->uuid('enquiry_id')->nullable()->index();
        });
    }

    public function down(): void
    {
        Schema::table('salons', function (Blueprint $table) {
            $table->dropIndex(['enquiry_id']);
            $table->dropColumn('enquiry_id');
        });
    }
};
