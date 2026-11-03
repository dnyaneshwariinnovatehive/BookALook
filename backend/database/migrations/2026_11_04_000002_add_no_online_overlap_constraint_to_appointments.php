<?php

use App\Services\BookingPolicyService;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * PostgreSQL refuses two overlapping ONLINE bookings for the same staff
     * member, whatever the application does.
     *
     * Exactly the rule the booking flow already applies (AvailabilityService):
     *   - same appointed_provider_id, same appointment_date;
     *   - both in a status that holds the chair (BookingPolicyService::
     *     BLOCKING_STATUSES): pending_payment, scheduled, confirmed,
     *     in_progress, completed — cancelled, no_show, rescheduled and
     *     awaiting_reschedule never block;
     *   - half-open [start, end): a booking ending at 11:00 and one starting
     *     at 11:00 do not clash.
     *
     * Only booking_source = 'online'. Walk-ins may overlap on purpose: the
     * desk is shown the clash and can squeeze someone in (WalkInService).
     * Rows whose end is not after their start (one completed walk-in ran past
     * midnight) are outside the rule rather than breaking it.
     *
     * Times are the salon's local wall-clock (date + time columns, no zone),
     * so a plain tsrange is the faithful interval.
     *
     * Pre-check: refuses to run if any existing rows would violate it, and
     * lists them. Production on 2026-11-03: 0 online/online overlaps.
     * Locking: ADD CONSTRAINT holds an exclusive lock while it builds; the
     * table had 710 rows (milliseconds). btree_gist is a trusted extension, so
     * the database owner can create it without superuser rights.
     *
     * If BLOCKING_STATUSES ever changes, this constraint must be recreated.
     */
    public function up(): void
    {
        if (DB::getDriverName() !== 'pgsql') {
            return; // exclusion constraints are PostgreSQL-only; tests on SQLite skip it
        }

        $statuses = implode(',', array_map(fn ($s) => DB::getPdo()->quote($s), BookingPolicyService::BLOCKING_STATUSES));
        $scope = "booking_source = 'online' AND status IN ({$statuses}) AND end_time > start_time";
        $scopeOf = fn (string $t) => "{$t}.booking_source = 'online' AND {$t}.status IN ({$statuses}) AND {$t}.end_time > {$t}.start_time";

        $clashes = DB::select("
            select a.id as a, b.id as b
              from appointments a
              join appointments b
                on a.appointed_provider_id = b.appointed_provider_id
               and a.appointment_date = b.appointment_date
               and a.id < b.id
               and a.start_time < b.end_time and b.start_time < a.end_time
             where (" . $scopeOf('a') . ') and (' . $scopeOf('b') . ')
             limit 20');

        if ($clashes !== []) {
            $pairs = implode('; ', array_map(fn ($r) => "{$r->a} x {$r->b}", $clashes));
            throw new RuntimeException("Overlapping online bookings exist, resolve them first: {$pairs}");
        }

        DB::statement('CREATE EXTENSION IF NOT EXISTS btree_gist');
        DB::statement("
            ALTER TABLE appointments
              ADD CONSTRAINT appointments_no_online_overlap
              EXCLUDE USING gist (
                appointed_provider_id WITH =,
                tsrange(appointment_date + start_time, appointment_date + end_time, '[)') WITH &&
              ) WHERE ({$scope})");
    }

    public function down(): void
    {
        if (DB::getDriverName() !== 'pgsql') {
            return;
        }

        // The extension is left installed: other objects may come to use it.
        DB::statement('ALTER TABLE appointments DROP CONSTRAINT IF EXISTS appointments_no_online_overlap');
    }

};
