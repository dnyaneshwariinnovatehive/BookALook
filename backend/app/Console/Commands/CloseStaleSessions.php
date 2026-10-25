<?php

namespace App\Console\Commands;

use App\Models\Appointment;
use App\Models\User;
use App\Services\AppointmentCheckInService;
use App\Services\Notifications\NotificationService;
use App\Support\Notifications\NotificationType;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Close visits that were started but never finished.
 *
 * Staff start a session by scanning the customer in, and finish it by collecting
 * the balance. When nobody presses "collect", the visit stayed in progress for
 * ever: never invoiced, never in a payout, no rating prompt. A day after it
 * started it is completed here as though the balance was taken in cash at the
 * counter, which is what almost always happened, and the owner is told so they
 * can correct it if not.
 */
class CloseStaleSessions extends Command
{
    protected $signature = 'app:close-stale-sessions {--hours=24 : How long after starting a visit is closed}';

    protected $description = 'Completes appointments left in progress for more than a day';

    public const NOTE = 'Closed automatically: the salon did not complete this visit within a day of starting it.';

    public function handle(AppointmentCheckInService $checkIn, NotificationService $notifications): int
    {
        $cutoff = now()->subHours(max(1, (int) $this->option('hours')));

        $ids = Appointment::where('status', 'in_progress')
            ->where(fn ($q) => $q->where('started_at', '<=', $cutoff)
                // A session with no start time recorded is judged by its date.
                ->orWhere(fn ($q) => $q->whereNull('started_at')
                    ->whereDate('appointment_date', '<', $cutoff->toDateString())))
            ->pluck('id');

        $closed = 0;

        foreach ($ids as $id) {
            try {
                $appointment = DB::transaction(function () use ($id, $checkIn) {
                    // Re-read under a lock: staff may finish it themselves while
                    // this runs, and that must win.
                    $appointment = Appointment::whereKey($id)->lockForUpdate()->first();

                    if (! $appointment || $appointment->status !== 'in_progress') {
                        return null;
                    }

                    $actor = User::find($appointment->salon?->admin_id)
                        ?? $appointment->servingProvider?->user
                        ?? $appointment->appointedProvider?->user;

                    if (! $actor) {
                        return null;
                    }

                    $checkIn->collectPaymentAndComplete(
                        $appointment->load($checkIn->relations()),
                        'cash',
                        $actor,
                        self::NOTE
                    );

                    return $appointment->fresh();
                });
            } catch (\Throwable $e) {
                Log::warning('Could not close a stale session', ['appointment_id' => $id, 'error' => $e->getMessage()]);

                continue;
            }

            if (! $appointment) {
                continue;
            }

            $closed++;

            try {
                $notifications->send(
                    $appointment->salon?->admin_id,
                    NotificationType::GENERAL,
                    'Visit closed automatically',
                    'A visit started on ' . \Carbon\Carbon::parse($appointment->appointment_date)->format('d M Y')
                        . ' was never completed, so it has been closed with the balance recorded as cash. '
                        . 'If that is not right, contact BookALook support.',
                    ['appointment_id' => $appointment->id],
                    salon: $appointment->salon,
                    dedupeKey: 'stale_session_closed:' . $appointment->id,
                );
            } catch (\Throwable $e) {
                Log::warning('Could not tell the owner about a closed session', ['appointment_id' => $appointment->id]);
            }
        }

        $this->info("Closed {$closed} stale session(s).");

        return self::SUCCESS;
    }
}
