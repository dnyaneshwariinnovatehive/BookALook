<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\Salon;
use App\Models\SalonPayout;
use App\Models\ServiceProvider;
use App\Models\User;
use App\Services\PayoutService;
use App\Support\PayoutCycle;
use Carbon\Carbon;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Phase 5 database rules, tested against a real PostgreSQL (skipped elsewhere).
 *
 * Run against a disposable PostgreSQL database that has been migrated:
 *
 *   DB_CONNECTION=pgsql DB_DATABASE=bookalook_test ... php artisan migrate:fresh --force
 *   DB_CONNECTION=pgsql DB_DATABASE=bookalook_test ... vendor/bin/phpunit tests/Feature/PostgresIntegrityTest.php
 *
 * No wrapping transaction: rows are committed so a SECOND connection can race
 * them for real, and each test deletes what it made.
 */
class PostgresIntegrityTest extends TestCase
{
    private string $u;

    private array $made = ['appointments' => [], 'salon_payouts' => [], 'service_providers' => [], 'salons' => [], 'users' => []];

    private Salon $salon;

    private ServiceProvider $p1;

    private ServiceProvider $p2;

    protected function setUp(): void
    {
        parent::setUp();

        if (DB::getDriverName() !== 'pgsql') {
            $this->markTestSkipped('PostgreSQL-only: exclusion constraints and concurrency.');
        }

        config(['database.connections.pgsql_b' => config('database.connections.pgsql')]);

        $this->u = substr(bin2hex(random_bytes(6)), 0, 8);
        $owner = $this->track(User::create(['id' => (string) Str::uuid(), 'role' => 'admin', 'name' => "O {$this->u}", 'phone' => '6'.random_int(100000000, 999999999), 'password_hash' => 'x', 'is_active' => true]));
        $staff = $this->track(User::create(['id' => (string) Str::uuid(), 'role' => 'service_provider', 'name' => "S {$this->u}", 'phone' => '6'.random_int(100000000, 999999999), 'password_hash' => 'x', 'is_active' => true]));
        $this->salon = $this->track(Salon::create(['admin_id' => $owner->id, 'name' => "PG {$this->u}", 'slug' => "pg-{$this->u}", 'address' => 'x', 'status' => 'active', 'submitted_by' => $owner->id]));
        $this->p1 = $this->track(ServiceProvider::create(['user_id' => $owner->id, 'salon_id' => $this->salon->id, 'is_active' => true]));
        $this->p2 = $this->track(ServiceProvider::create(['user_id' => $staff->id, 'salon_id' => $this->salon->id, 'is_active' => true]));
    }

    protected function tearDown(): void
    {
        if (DB::getDriverName() === 'pgsql') {
            DB::table('salon_payout_items')->whereIn('salon_payout_id', SalonPayout::where('salon_id', $this->salon->id ?? null)->pluck('id'))->delete();
            SalonPayout::where('salon_id', $this->salon->id ?? null)->delete();
            Appointment::where('salon_id', $this->salon->id ?? null)->delete();
            foreach (['service_providers', 'salons', 'users'] as $table) {
                DB::table($table)->whereIn('id', $this->made[$table])->delete();
            }
            DB::disconnect('pgsql_b');
        }
        parent::tearDown();
    }

    private function track($model)
    {
        $this->made[$model->getTable()][] = $model->getKey();

        return $model;
    }

    private function row(ServiceProvider $p, string $start, string $end, array $over = []): array
    {
        return $over + [
            'id' => (string) Str::uuid(), 'salon_id' => $this->salon->id, 'appointed_provider_id' => $p->id,
            'booking_source' => 'online', 'appointment_date' => '2026-12-01', 'start_time' => $start, 'end_time' => $end,
            'status' => 'scheduled', 'total_amount' => 100, 'advance_amount' => 0, 'balance_amount' => 100,
            'created_at' => now(), 'updated_at' => now(),
        ];
    }

    private function insert(array $row, string $connection = 'pgsql'): void
    {
        DB::connection($connection)->table('appointments')->insert($row);
    }

    private function assertClash(callable $insert): void
    {
        try {
            $insert();
            $this->fail('expected the database to refuse an overlapping online booking');
        } catch (QueryException $e) {
            $this->assertSame('23P01', $e->getCode(), $e->getMessage());
        }
    }

    // --- The rules exist and are valid -----------------------------------------------

    public function test_the_constraint_and_index_exist_and_are_valid(): void
    {
        $c = DB::selectOne("select pg_get_constraintdef(oid) as def from pg_constraint where conname = 'appointments_no_online_overlap'");
        $this->assertNotNull($c, 'exclusion constraint exists');
        $this->assertStringContainsString("booking_source)::text = 'online'", $c->def);

        $i = DB::selectOne("select i.indisvalid as valid, i.indisunique as uniq from pg_index i join pg_class c on c.oid = i.indexrelid where c.relname = 'salon_payouts_one_per_cycle'");
        $this->assertTrue((bool) $i->valid);
        $this->assertTrue((bool) $i->uniq);

        $push = DB::selectOne("select i.indisvalid as valid from pg_index i join pg_class c on c.oid = i.indexrelid where c.relname = 'notifications_push_owed_idx'");
        $this->assertTrue((bool) $push->valid, 'Phase 4 partial index built CONCURRENTLY and valid');
    }

    // --- Appointments ---------------------------------------------------------------

    public function test_overlapping_online_bookings_for_one_provider_are_refused(): void
    {
        $this->insert($this->row($this->p1, '10:00:00', '11:00:00'));
        $this->assertClash(fn () => $this->insert($this->row($this->p1, '10:30:00', '11:30:00')));
        $this->assertClash(fn () => $this->insert($this->row($this->p1, '09:00:00', '12:00:00'))); // contains it
    }

    public function test_adjacent_bookings_and_other_providers_are_fine(): void
    {
        $this->insert($this->row($this->p1, '10:00:00', '10:30:00'));
        $this->insert($this->row($this->p1, '10:30:00', '11:00:00')); // starts as the other ends
        $this->insert($this->row($this->p2, '10:00:00', '10:30:00')); // another provider
        $this->insert($this->row($this->p1, '10:00:00', '10:30:00', ['appointment_date' => '2026-12-02'])); // another day

        $this->assertSame(4, Appointment::where('salon_id', $this->salon->id)->count());
    }

    public function test_statuses_that_do_not_hold_the_chair_never_block(): void
    {
        foreach (['cancelled', 'no_show', 'rescheduled', 'awaiting_reschedule'] as $i => $status) {
            $this->insert($this->row($this->p1, '10:00:00', '11:00:00', ['status' => $status]));
        }
        $this->insert($this->row($this->p1, '10:00:00', '11:00:00')); // the slot is free

        $this->assertClash(fn () => $this->insert($this->row($this->p1, '10:00:00', '11:00:00', ['status' => 'completed'])));
    }

    public function test_walk_ins_may_still_be_squeezed_in(): void
    {
        $this->insert($this->row($this->p1, '10:00:00', '11:00:00'));
        $this->insert($this->row($this->p1, '10:15:00', '10:45:00', ['booking_source' => 'walk_in']));
        $this->insert($this->row($this->p1, '10:20:00', '10:50:00', ['booking_source' => 'walk_in']));

        $this->assertSame(3, Appointment::where('salon_id', $this->salon->id)->count());
    }

    public function test_a_booking_running_past_midnight_is_outside_the_rule_not_an_error(): void
    {
        $this->insert($this->row($this->p1, '22:00:00', '02:00:00', ['status' => 'completed']));
        $this->insert($this->row($this->p1, '23:00:00', '23:30:00'));

        $this->assertSame(2, Appointment::where('salon_id', $this->salon->id)->count());
    }

    public function test_reactivating_a_cancelled_booking_into_a_taken_slot_is_refused(): void
    {
        $this->insert($this->row($this->p1, '10:00:00', '11:00:00'));
        $cancelled = $this->row($this->p1, '10:00:00', '11:00:00', ['status' => 'cancelled']);
        $this->insert($cancelled);

        $this->assertClash(fn () => DB::table('appointments')->where('id', $cancelled['id'])->update(['status' => 'scheduled']));
    }

    public function test_rescheduling_frees_the_old_slot_first_in_one_transaction(): void
    {
        $old = $this->row($this->p1, '10:00:00', '11:00:00');
        $this->insert($old);

        // New time overlaps the booking's own old slot: fine once the old one
        // stops holding the chair inside the same transaction (the controller's order).
        DB::transaction(function () use ($old) {
            DB::table('appointments')->where('id', $old['id'])->update(['status' => 'rescheduled']);
            $this->insert($this->row($this->p1, '10:30:00', '11:30:00', ['rescheduled_from_id' => $old['id']]));
        });

        // The old order (insert first) would have been refused.
        $other = $this->row($this->p2, '10:00:00', '11:00:00');
        $this->insert($other);
        $this->assertClash(fn () => DB::transaction(function () use ($other) {
            $this->insert($this->row($this->p2, '10:30:00', '11:30:00', ['rescheduled_from_id' => $other['id']]));
            DB::table('appointments')->where('id', $other['id'])->update(['status' => 'rescheduled']);
        }));
        $this->assertSame('scheduled', DB::table('appointments')->where('id', $other['id'])->value('status'), 'rolled back whole');
    }

    public function test_two_connections_racing_for_one_slot_only_one_wins(): void
    {
        $b = DB::connection('pgsql_b');

        DB::beginTransaction();
        $this->insert($this->row($this->p1, '10:00:00', '11:00:00')); // uncommitted on connection A

        // Connection B tries the same slot: it must wait for A, not slip past.
        $b->statement("SET lock_timeout = '1s'");
        try {
            $this->insert($this->row($this->p1, '10:15:00', '10:45:00'), 'pgsql_b');
            $this->fail('B should have waited on A');
        } catch (QueryException $e) {
            $this->assertSame('55P03', $e->getCode(), 'B blocked behind A (lock timeout)');
        }

        DB::commit();

        // Now A is committed: B is refused outright.
        $this->assertClash(fn () => $this->insert($this->row($this->p1, '10:15:00', '10:45:00'), 'pgsql_b'));
    }

    public function test_if_the_first_racer_rolls_back_the_second_gets_the_slot(): void
    {
        DB::beginTransaction();
        $this->insert($this->row($this->p1, '10:00:00', '11:00:00'));
        DB::rollBack();

        $this->insert($this->row($this->p1, '10:00:00', '11:00:00'), 'pgsql_b');
        $this->assertSame(1, Appointment::where('salon_id', $this->salon->id)->count());
    }

    public function test_the_booking_api_turns_a_clash_into_a_409_not_a_raw_error(): void
    {
        $this->insert($this->row($this->p1, '10:00:00', '11:00:00'));
        try {
            $this->insert($this->row($this->p1, '10:00:00', '11:00:00'));
        } catch (QueryException $e) {
            $isClash = new \ReflectionMethod(\App\Http\Controllers\Api\Customer\AppointmentController::class, 'isSlotClash');
            $this->assertTrue($isClash->invoke(null, $e));

            return;
        }
        $this->fail('expected a clash');
    }

    // --- Payouts --------------------------------------------------------------------

    private function completedBooking(string $date): void
    {
        $this->insert($this->row($this->p1, '10:00:00', '10:30:00', ['appointment_date' => $date, 'status' => 'completed', 'total_amount' => 500, 'balance_amount' => 500]));
    }

    public function test_a_second_payout_for_one_protected_cycle_is_refused(): void
    {
        $row = fn () => ['id' => (string) Str::uuid(), 'salon_id' => $this->salon->id, 'cycle_type' => 'weekly',
            'cycle_start_date' => '2026-10-05', 'cycle_end_date' => '2026-10-11', 'status' => 'pending', 'created_at' => now(), 'updated_at' => now()];
        DB::table('salon_payouts')->insert($row());

        $this->expectException(\Illuminate\Database\UniqueConstraintViolationException::class);
        DB::table('salon_payouts')->insert($row());
    }

    public function test_cycles_before_the_cutoff_are_untouched_by_the_rule(): void
    {
        $row = fn () => ['id' => (string) Str::uuid(), 'salon_id' => $this->salon->id, 'cycle_type' => 'weekly',
            'cycle_start_date' => '2026-09-07', 'cycle_end_date' => '2026-09-13', 'status' => 'pending', 'created_at' => now(), 'updated_at' => now()];
        DB::table('salon_payouts')->insert($row());
        DB::table('salon_payouts')->insert($row());

        $this->assertSame(2, SalonPayout::where('salon_id', $this->salon->id)->count());
    }

    public function test_calculate_recovers_from_losing_the_insert_race(): void
    {
        $this->completedBooking('2026-10-06');
        $service = app(PayoutService::class);
        $start = Carbon::parse('2026-10-05');
        $end = Carbon::parse('2026-10-11');

        // Another run inserted the row between this run's look-up and insert:
        // simulate by inserting it, then calling the retry path directly.
        DB::table('salon_payouts')->insert(['id' => (string) Str::uuid(), 'salon_id' => $this->salon->id, 'cycle_type' => PayoutCycle::WEEKLY,
            'cycle_start_date' => '2026-10-05', 'cycle_end_date' => '2026-10-11', 'status' => 'pending', 'created_at' => now(), 'updated_at' => now()]);
        $payout = $service->calculate($this->salon->id, $start, $end, PayoutCycle::WEEKLY);

        $this->assertSame(1, SalonPayout::where('salon_id', $this->salon->id)->count());
        $this->assertSame(1, (int) $payout->fresh()->appointments_count);
    }

    public function test_parallel_payout_runs_leave_one_payout_with_its_items_once(): void
    {
        $this->completedBooking('2026-10-06');
        $this->completedBooking('2026-10-07');

        $code = "app(App\\Services\\PayoutService::class)->calculate('{$this->salon->id}', Carbon\\Carbon::parse('2026-10-05'), Carbon\\Carbon::parse('2026-10-11'), 'weekly'); echo 'ok';";
        $procs = [];
        foreach (range(1, 6) as $i) {
            $procs[$i] = proc_open([PHP_BINARY, base_path('artisan'), 'tinker', '--execute=' . $code], [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes[$i], base_path());
        }
        $out = [];
        foreach ($procs as $i => $p) {
            $out[$i] = stream_get_contents($pipes[$i][1]) . stream_get_contents($pipes[$i][2]);
            proc_close($p);
        }

        $payouts = SalonPayout::where('salon_id', $this->salon->id)->get();
        $this->assertCount(1, $payouts, 'one payout row, not one per run: ' . implode(' | ', $out));
        $this->assertSame(2, DB::table('salon_payout_items')->where('salon_payout_id', $payouts[0]->id)->where('kind', 'booking')->count(), 'each booking settled once');
    }
}
