<?php

namespace App\Console\Commands;

use App\Models\Appointment;
use App\Services\Notifications\NotificationService;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

/**
 * Marks yesterday's untouched appointments as no-shows, and tells the customer.
 *
 * The bulk `update()` this used to be is what makes the notification awkward:
 * it can flip a thousand rows without ever loading one, so there is nothing to
 * attach a notice to. The appointments are now fetched first — a day's worth,
 * which is a page of a salon, not a table — because "you were marked as missed"
 * is a thing that happens to a person and has to be said to them.
 *
 * Skipped entirely for walk-ins, who have no account to notify. Their row still
 * moves to no_show; there is simply nowhere to send the news.
 */
class MarkNoShowAppointments extends Command
{
    /**
     * The name and signature of the console command.
     *
     * @var string
     */
    protected $signature = 'app:mark-no-shows';

    /**
     * The console command description.
     *
     * @var string
     */
    protected $description = 'Marks scheduled appointments from previous days as no_show';

    /**
     * Execute the console command.
     */
    public function handle(NotificationService $notifications)
    {
        $yesterday = Carbon::yesterday();

        // Collect the ids first, then update by them.
        //
        // The obvious version of this — update, then re-query for `no_show` —
        // is wrong in a way that only shows up days later: it cannot tell an
        // appointment swept a minute ago from one marked last month, so every
        // run would go back over the entire history. The dedupe key would stop
        // the duplicates, but the command would still do a full table scan
        // forever and would notify about old visits on its very first run.
        $sweptIds = Appointment::query()
            ->where('status', 'scheduled')
            ->whereDate('appointment_date', '<', $yesterday)
            ->pluck('id');

        if ($sweptIds->isEmpty()) {
            $this->info('No appointments to mark as no-show.');

            return self::SUCCESS;
        }

        $swept = Appointment::whereIn('id', $sweptIds)->update([
            'status' => 'no_show',
            'no_show_at' => now(),
        ]);

        // Read back the same rows, now carrying the new status, so the set that
        // gets notified about and the set that got swept are the same set by
        // construction rather than by a query that happens to agree.
        $sweptAppointments = Appointment::with(['salon', 'customer'])
            ->whereIn('id', $sweptIds)
            ->whereNotNull('customer_id')
            ->whereHas('customer')
            ->get();

        $notified = 0;

        foreach ($sweptAppointments as $appointment) {
            // Keyed on the appointment, because this command is scheduled daily
            // and a day where it runs twice — a deploy mid-sweep, a manual retry
            // after a failure — must not tell a customer they missed a visit they
            // are already being told about.
            $dedupeKey = 'appointment_no_show:'.$appointment->id;

            try {
                $notification = $notifications->appointmentMarkedNoShow(
                    $appointment,
                    $appointment->salon?->name ?? 'the salon',
                    $dedupeKey,
                );

                if ($notification) {
                    $notified++;
                }
            } catch (\Throwable $e) {
                // One unreachable customer must not stop the sweep. The row is
                // already marked; a missing notification is a much smaller
                // problem than a sweep that dies half way through.
                Log::warning('Could not send a no-show notification', [
                    'appointment_id' => $appointment->id,
                    'error' => $e->getMessage(),
                ]);
            }
        }

        $this->info("Marked {$swept} appointments as no-show, and notified {$notified} customers.");

        return self::SUCCESS;
    }
}
