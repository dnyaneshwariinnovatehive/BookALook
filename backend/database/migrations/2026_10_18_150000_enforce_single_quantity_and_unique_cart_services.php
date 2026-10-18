<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        // 1. Data cleanup on existing carts before applying constraints.
        // For duplicate individual-service rows in the same cart, retain one canonical row
        // (preferring a row with preferred_provider_id or the latest updated_at) and remove redundant lines.
        $duplicateGroups = DB::table('cart_items')
            ->whereNotNull('service_id')
            ->select('cart_id', 'service_id', DB::raw('COUNT(*) as count'))
            ->groupBy('cart_id', 'service_id')
            ->havingRaw('COUNT(*) > 1')
            ->get();

        foreach ($duplicateGroups as $group) {
            $items = DB::table('cart_items')
                ->where('cart_id', $group->cart_id)
                ->where('service_id', $group->service_id)
                ->orderByRaw('CASE WHEN preferred_provider_id IS NOT NULL THEN 0 ELSE 1 END')
                ->orderByDesc('updated_at')
                ->get();

            if ($items->count() > 1) {
                $canonical = $items->first();
                $redundantIds = $items->slice(1)->pluck('id');

                DB::table('cart_items')
                    ->whereIn('id', $redundantIds)
                    ->delete();
            }
        }

        // Clamp remaining individual-service item quantities to 1.
        // Direct combo items (where service_id is null) are completely untouched.
        DB::table('cart_items')
            ->whereNotNull('service_id')
            ->where('quantity', '!=', 1)
            ->update(['quantity' => 1]);

        // 2. Add partial unique index for individual-service identity within a cart.
        // Allows multiple NULL service_id values for direct combo items.
        // Supported by both PostgreSQL and SQLite (3.8.0+).
        DB::statement('CREATE UNIQUE INDEX unique_active_cart_service ON cart_items (cart_id, service_id) WHERE service_id IS NOT NULL');

        // 3. Add check constraint on PostgreSQL ensuring quantity = 1 whenever service_id is not null.
        if (DB::getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE cart_items ADD CONSTRAINT check_service_quantity_is_one CHECK (service_id IS NULL OR quantity = 1)');
        }
    }

    public function down(): void
    {
        if (DB::getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE cart_items DROP CONSTRAINT IF EXISTS check_service_quantity_is_one');
        }

        DB::statement('DROP INDEX IF EXISTS unique_active_cart_service');
    }
};
