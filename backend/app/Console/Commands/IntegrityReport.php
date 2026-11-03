<?php

namespace App\Console\Commands;

use App\Services\BookingPolicyService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Read-only checks to run BEFORE adding database constraints (Phase 5).
 *
 *   php artisan app:integrity-report
 *
 * Changes nothing. Prints counts and record ids only — no names, phones or
 * amounts. PostgreSQL only (it asks PostgreSQL about extensions and sizes).
 */
class IntegrityReport extends Command
{
    protected $signature = 'app:integrity-report {--samples=15 : How many example ids to list per finding}';

    protected $description = 'Read-only report of records that would violate the proposed appointment and payout constraints';

    public function handle(): int
    {
        if (DB::getDriverName() !== 'pgsql') {
            $this->error('This report is for PostgreSQL.');

            return self::FAILURE;
        }

        $limit = max(1, (int) $this->option('samples'));
        $blocking = BookingPolicyService::BLOCKING_STATUSES;
        $in = implode(',', array_map(fn ($s) => DB::getPdo()->quote($s), $blocking));

        $this->line('== Environment');
        $this->line('  PostgreSQL: ' . DB::selectOne('select version() as v')->v);
        $ext = DB::selectOne("select (select installed_version from pg_extension e where e.extname = 'btree_gist') as installed, (select default_version from pg_available_extensions where name = 'btree_gist') as available");
        $this->line('  btree_gist available: ' . ($ext->available ?? 'NO') . ', installed: ' . ($ext->installed ?? 'no'));
        $role = DB::selectOne("select current_user as u, rolsuper as su, (select datdba = r.oid from pg_database where datname = current_database()) as owns_db from pg_roles r where rolname = current_user");
        $this->line("  app role: {$role->u}, superuser: " . ($role->su ? 'yes' : 'no') . ', owns database: ' . ($role->owns_db ? 'yes' : 'no'));
        foreach (['appointments', 'salon_payouts', 'salon_payout_items'] as $t) {
            $s = DB::selectOne("select count(*) as n, pg_size_pretty(pg_total_relation_size('{$t}')) as size from {$t}");
            $this->line("  {$t}: {$s->n} rows, {$s->size}");
        }

        $this->newLine();
        $this->line('== Appointments');
        foreach (DB::select('select status, booking_source, count(*) as n from appointments group by status, booking_source order by status, booking_source') as $r) {
            $this->line(sprintf('  %-16s %-10s %d', $r->status, $r->booking_source, $r->n));
        }

        $bad = DB::select("select id, appointment_date, start_time, end_time, status from appointments where status in ({$in}) and end_time <= start_time limit {$limit}");
        $badCount = DB::selectOne("select count(*) as n from appointments where status in ({$in}) and end_time <= start_time")->n;
        $this->line("  blocking appointments with end_time <= start_time (zero length or past midnight): {$badCount}");
        foreach ($bad as $r) {
            $this->line("    {$r->id}  {$r->appointment_date} {$r->start_time}-{$r->end_time}  {$r->status}");
        }

        $overlapSql = "from appointments a join appointments b
            on a.appointed_provider_id = b.appointed_provider_id
           and a.appointment_date = b.appointment_date
           and a.id < b.id
           and a.start_time < b.end_time and b.start_time < a.end_time
           and a.end_time > a.start_time and b.end_time > b.start_time
         where a.status in ({$in}) and b.status in ({$in})";

        $this->line('  overlapping pairs on the same provider, both in blocking statuses (' . implode(', ', $blocking) . '):');
        foreach (DB::select("select least(a.booking_source, b.booking_source) || ' + ' || greatest(a.booking_source, b.booking_source) as kinds, count(*) as n {$overlapSql} group by 1 order by 1") as $r) {
            $this->line(sprintf('    %-22s %d', $r->kinds, $r->n));
        }
        $future = DB::selectOne("select count(*) as n {$overlapSql} and a.appointment_date >= current_date")->n;
        $this->line("    of which today or later: {$future}");
        foreach (DB::select("select a.id as a_id, b.id as b_id, a.appointment_date as d, a.start_time as a_s, a.end_time as a_e, a.status as a_st, a.booking_source as a_src, b.start_time as b_s, b.end_time as b_e, b.status as b_st, b.booking_source as b_src {$overlapSql} order by a.appointment_date desc limit {$limit}") as $r) {
            $this->line("    {$r->d}  {$r->a_id} {$r->a_s}-{$r->a_e} {$r->a_st}/{$r->a_src}  x  {$r->b_id} {$r->b_s}-{$r->b_e} {$r->b_st}/{$r->b_src}");
        }

        $this->newLine();
        $this->line('== Payouts');
        $dupCount = DB::selectOne('select count(*) as n from (select 1 from salon_payouts group by salon_id, cycle_type, cycle_start_date having count(*) > 1) d')->n;
        $this->line("  (salon_id, cycle_type, cycle_start_date) groups with more than one payout: {$dupCount}");
        foreach (DB::select("select salon_id, cycle_type, cycle_start_date, count(*) as n, string_agg(id::text || ':' || status, ', ' order by created_at) as rows from salon_payouts group by salon_id, cycle_type, cycle_start_date having count(*) > 1 order by cycle_start_date desc limit {$limit}") as $r) {
            $this->line("    salon {$r->salon_id} {$r->cycle_type} {$r->cycle_start_date}: {$r->n} rows -> {$r->rows}");
        }
        foreach (DB::select('select status, cycle_type, count(*) as n from salon_payouts group by status, cycle_type order by status, cycle_type') as $r) {
            $this->line(sprintf('  %-12s %-8s %d', $r->status, $r->cycle_type, $r->n));
        }
        $existing = DB::select("select indexname, indexdef from pg_indexes where tablename = 'salon_payouts'");
        $this->line('  existing indexes on salon_payouts:');
        foreach ($existing as $i) {
            $this->line("    {$i->indexname}: {$i->indexdef}");
        }

        $this->newLine();
        $this->line('Nothing was changed.');

        return self::SUCCESS;
    }
}
