<?php

namespace App\Console\Commands;

use App\Models\Appointment;
use App\Services\Notifications\NotificationService;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

/**
 * Tell customers about an appointment that is about to happen.
 *
 * The scheduler runs this every fifteen minutes, which sounds like the wrong tool
 * for a reminder measured in hours. The reason is the failure mode: a job that
 * runs on an exact schedule at an exact minute is one missed cron tick away from
 * never reminding anybody, and nobody notices a missing reminder — the customer
 * simply does not get one and there is no evidence it was ever due. A window
 * that is wide, recomputed from the data on every pass, and made idempotent
 * means a missed tick costs nothing and a duplicate tick costs nothing either.
 *
 * That idempotency is the whole design. Eligibility is a *window* (starting
 * within the lead time) rather than an instant, so the same appointment is due
 * for four consecutive runs, and the dedupe key is what makes those four runs
 * produce exactly one notification. The alternative — remembering what was sent
 * in a cache — is wrong the moment the cache is cleared, which is precisely when
 * a reminder must not be lost.
 */
class SendAppointmentReminders extends Command
{
    protected $signature = 'app:send-appointment-reminders
                            {--lead= : Override the lead time in hours (APPOINTMENT_REMINDER_LEAD_HOURS)}
                            {--dry-run : List what would be reminded without notifying anyone}';

    protected $description = 'Sends a reminder to customers whose appointment starts within the lead time';

    /**
     * Reminders only go to bookings that will actually be served: a cancelled or
     * already-moved booking has nothing to remind anybody about, and `pending_payment`
     * is excluded because that customer has not finished making the booking yet —
     * telling them it is coming reads as a demand rather than a courtesy.
     */
    private const REMINDABLE_STATUSES = ['scheduled', 'confirmed'];

    public function handle(NotificationService $notifications): int
    {
        $leadHours = $this->leadHours();

        if ($leadHours === null) {
            $this->info('Appointment reminders are disabled (APPOINTMENT_REMINDER_LEAD_HOURS is 0).');

            return self::SUCCESS;
        }

        $now = Carbon::now();

        // The upper bound of the window is "now plus the lead time" rather than
        // "exactly the lead time", so a tick that runs late still catches the
        // appointments it should have. The lower bound is exclusive, which is
        // what stops an appointment being re-considered once it is inside the
        // window and therefore being offered as newly due forever.
        $windowStart = $now->copy();
        $windowEnd = $now->copy()->addHours($leadHours);

        $due = Appointment::query()
            ->whereNotNull('customer_id')
            ->whereIn('status', self::REMINDABLE_STATUSES)
            ->whereBetween('appointment_date', [
                $windowStart->toDateString(),
                $windowEnd->toDateString(),
            ])
            ->whereHas('customer')
            ->with(['salon', 'customer', 'appointedProvider'])
            ->orderBy('appointment_date')
            ->get()
            // The date column alone is far too coarse: it would remind somebody
            // about a 9am appointment at 11pm the night before. Filtering the
            // real start datetime in PHP is what keeps the reminder to the
            // configured lead time, and it is a bounded set — one day's bookings.
            ->filter(function (Appointment $appointment) use ($windowStart, $windowEnd) {
                $startsAt = $this->startsAt($appointment);

                return $startsAt !== null
                    && $startsAt->greaterThan($windowStart)
                    && $startsAt->lessThanOrEqualTo($windowEnd);
            });

        if ($due->isEmpty()) {
            $this->info('No appointments are due a reminder right now.');

            return self::SUCCESS;
        }

        $sent = 0;
        $skipped = 0;

        foreach ($due as $appointment) {
            $salonName = $appointment->salon?->name ?? 'your salon';

            if ($this->option('dry-run')) {
                $this->line(sprintf(
                    'Would remind %s about the appointment at %s (%s).',
                    $appointment->customer?->phone ?? $appointment->customer_id,
                    $salonName,
                    (string) $this->startsAt($appointment)?->format('M d, Y h:i A'),
                ));
                $skipped++;

                continue;
            }

            // Keyed on the appointment and the day of the appointment, not on the
            // run time: a run at 09:00 and a run at 09:07 must not be two
            // different keys, or the dedupe never fires and the customer gets
            // two reminders for the same visit.
            $dedupeKey = sprintf('reminder:%s:%s', $appointment->id, $appointment->appointment_date);

            try {
                $notification = $notifications->appointmentReminder(
                    $appointment,
                    $salonName,
                    $this->dateTimeLabel($appointment),
                    $dedupeKey,
                );

                if ($notification) {
                    $sent++;
                } else {
                    $skipped++;
                }
            } catch (\Throwable $e) {
                // One appointment that cannot be reminded must not stop the rest
                // of the window: the next tick will try this one again.
                $skipped++;

                Log::warning('Could not send an appointment reminder', [
                    'appointment_id' => $appointment->id,
                    'error' => $e->getMessage(),
                ]);
            }
        }

        $this->info(sprintf(
            'Reminders: %d sent, %d already sent or skipped%s.',
            $sent,
            $skipped,
            $this->option('dry-run') ? ' (dry run, nothing was sent)' : '',
        ));

        return self::SUCCESS;
    }

    /**
     * The lead time in hours, or null when reminders are switched off.
     *
     * Read from config rather than env directly so the scheduler, the tests and
     * the deploy docs all agree on one name. A value of 0 is the documented way
     * to turn reminders off without editing the schedule.
     */
    private function leadHours(): ?int
    {
        $raw = $this->option('lead') ?? config('services.push.appointment_reminder_lead_hours');

        $hours = (int) $raw;

        return $hours > 0 ? $hours : null;
    }

    /**
     * The real moment this appointment starts, or null if it cannot be worked out.
     *
     * `appointment_date` and `start_time` are stored separately — a date column
     * and a time-of-day column, neither of which the model casts — so they have
     * to be parsed and combined before anything can compare them to a clock.
     * Guarded rather than assumed, because a booking with an unparseable time
     * should be skipped quietly, not crash the whole window.
     */
    private function startsAt(Appointment $appointment): ?Carbon
    {
        if (! $appointment->appointment_date || ! $appointment->start_time) {
            return null;
        }

        try {
            return Carbon::parse(trim($appointment->appointment_date).' '.trim($appointment->start_time));
        } catch (\Throwable) {
            return null;
        }
    }

    /**
     * "Sep 26, 2026 at 4:30 PM" — the same wording the service uses elsewhere,
     * so a reminder and the confirmation a customer already read agree.
     */
    private function dateTimeLabel(Appointment $appointment): string
    {
        $startsAt = $this->startsAt($appointment);

        return $startsAt?->format('M d, Y').' at '.$startsAt?->format('h:i A') ?? 'your appointment time';
    }
}
