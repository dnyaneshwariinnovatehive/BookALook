<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * First-time offers now belong to salons. The platform-wide ones SuperAdmin
 * made are switched off — kept, not deleted, so past bookings that used them
 * still point at a real offer.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::table('first_time_offers')
            ->whereNull('salon_id')
            ->update(['is_active' => false, 'updated_at' => now()]);
    }

    public function down(): void
    {
        // Nothing to restore: which ones were live before is not recorded.
    }
};
