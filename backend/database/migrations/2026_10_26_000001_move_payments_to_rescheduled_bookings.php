<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Bookings rescheduled before the fix left their payments on the old row, where
 * refunds, the counter bill and payouts could not see them. Move each one to the
 * booking the chain of reschedules ends at, along with any first-time offer
 * redemption, and copy across who the booking is for.
 */
return new class extends Migration
{
    public function up(): void
    {
        $replacements = DB::table('appointments')
            ->whereNotNull('rescheduled_from_id')
            ->pluck('id', 'rescheduled_from_id'); // old id => new id

        foreach (DB::table('appointments')->where('status', 'rescheduled')->get() as $old) {
            $target = $old->id;
            $seen = [];
            while (isset($replacements[$target]) && ! isset($seen[$target])) {
                $seen[$target] = true;
                $target = $replacements[$target];
            }

            if ($target === $old->id) {
                continue;
            }

            DB::table('payments')
                ->where('appointment_id', $old->id)
                ->where('status', 'success')
                ->update(['appointment_id' => $target, 'updated_at' => now()]);

            DB::table('first_time_offer_redemptions')
                ->where('appointment_id', $old->id)
                ->update(['appointment_id' => $target]);

            $next = $replacements[$old->id];
            DB::table('appointments')->where('id', $next)->whereNull('first_time_offer_id')->update([
                'booked_for' => $old->booked_for ?? 'self',
                'recipient_name' => $old->recipient_name,
                'recipient_gender' => $old->recipient_gender,
                'recipient_phone' => $old->recipient_phone,
                'first_time_offer_id' => $old->first_time_offer_id,
                'first_time_discount_amount' => $old->first_time_discount_amount,
            ]);

            if ($old->customer_phone_hash) {
                DB::table('appointments')->where('id', $next)->whereNull('customer_phone_hash')
                    ->update(['customer_phone_hash' => $old->customer_phone_hash]);
            }
        }
    }

    public function down(): void
    {
        // Not reversed: the old placement was the bug.
    }
};
