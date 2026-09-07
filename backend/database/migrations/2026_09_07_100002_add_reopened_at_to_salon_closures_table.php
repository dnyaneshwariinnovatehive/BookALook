<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Re-opening a closed day marks the closure rather than deleting it.
 *
 * Deleting the row would cascade a null onto every appointment it released and
 * silently withdraw the free reschedule those customers were already promised.
 * It would also erase the record of why a day of bookings was cancelled, which
 * is the first thing anyone asks for in a dispute.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('salon_closures', function (Blueprint $table) {
            $table->timestamp('reopened_at')->nullable()->after('processed_at');
            $table->foreignUuid('reopened_by')->nullable()->after('reopened_at')
                ->constrained('users')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('salon_closures', function (Blueprint $table) {
            $table->dropConstrainedForeignId('reopened_by');
            $table->dropColumn('reopened_at');
        });
    }
};
