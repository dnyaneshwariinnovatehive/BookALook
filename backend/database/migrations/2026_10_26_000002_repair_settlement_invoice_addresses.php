<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Statements issued so far printed the salon's city as the city record's raw
 * JSON. The address is a frozen snapshot, so it is rebuilt once here from the
 * salon's address, city name and pincode, the way new statements now build it.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::table('settlement_invoices')
            ->where('salon_address', 'like', '%{"%')
            ->orderBy('id')
            ->get(['id', 'salon_id'])
            ->each(function ($invoice) {
                $salon = DB::table('salons')
                    ->leftJoin('cities', 'cities.id', '=', 'salons.city_id')
                    ->where('salons.id', $invoice->salon_id)
                    ->first(['salons.address', 'salons.pincode', 'cities.name as city']);

                $parts = $salon ? array_filter([$salon->address, $salon->city, $salon->pincode]) : [];

                DB::table('settlement_invoices')->where('id', $invoice->id)->update([
                    'salon_address' => $parts ? implode(', ', $parts) : null,
                ]);
            });
    }

    public function down(): void
    {
        // The broken text is not worth restoring.
    }
};
