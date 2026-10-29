<?php

namespace App\Console\Commands;

use App\Models\Salon;
use App\Services\CommissionDuesService;
use App\Services\Notifications\NotificationService;
use App\Support\Notifications\NotificationType;
use Carbon\Carbon;
use Illuminate\Console\Command;

/**
 * The daily pass over Commission Model salons that owe BookALook money.
 *
 * The steps themselves (banner, full payment online, deductions, paused
 * bookings, lock) are worked out live whenever anything asks, so nothing here
 * switches them on. This pass only talks to the owner: a reminder on the days
 * SuperAdmin set, and a notice the first time each new step starts. It also
 * tidies up once a salon has paid, so a step applied by hand does not carry
 * over to the next time it falls behind.
 */
class EnforceCommissionDues extends Command
{
    protected $signature = 'app:enforce-commission-dues';

    protected $description = 'Remind Commission Model salons about overdue commission and tell owners when a step starts';

    public function handle(CommissionDuesService $dues, NotificationService $notifications): int
    {
        $settings = $dues->settings();
        $reminded = 0;
        $stepped = 0;

        Salon::where('commission_opt_in', true)
            ->where('status', 'active')
            ->chunkById(100, function ($salons) use ($dues, $settings, $notifications, &$reminded, &$stepped) {
                foreach ($salons as $salon) {
                    $state = $dues->state($salon, $settings);

                    // Paid up (or below the minimum): clear what was set for
                    // the last time it fell behind.
                    if (! $state['applies'] || $state['below_minimum']) {
                        if ($salon->dues_notified_stage || $salon->dues_stage_override || $salon->dues_extended_until || $salon->dues_paused) {
                            $salon->forceFill([
                                'dues_notified_stage' => null,
                                'dues_stage_override' => null,
                                'dues_override_reason' => null,
                                'dues_extended_until' => null,
                                'dues_paused' => false,
                            ])->save();
                        }

                        continue;
                    }

                    if ($this->announceStep($salon, $state, $notifications)) {
                        $stepped++;
                    } elseif ($dues->isReminderDay($state, $settings)) {
                        $this->remind($salon, $state, $notifications);
                        $reminded++;
                    }
                }
            });

        $this->info("Dues reminders: {$reminded}. Step notices: {$stepped}.");

        return self::SUCCESS;
    }

    /** Tell the owner once when the salon reaches a stricter step. */
    private function announceStep(Salon $salon, array $state, NotificationService $notifications): bool
    {
        $stage = $state['stage'];
        if (! $stage || $stage === CommissionDuesService::STEP_REMINDER) {
            return false;
        }

        $order = array_flip(CommissionDuesService::STEPS);
        $previous = $salon->dues_notified_stage;
        if ($previous && isset($order[$previous]) && $order[$previous] >= $order[$stage]) {
            return false;
        }

        $notifications->send(
            recipient: $salon->admin_id,
            type: NotificationType::GENERAL,
            title: CommissionDuesService::LABELS[$stage] . ' · ' . $salon->name,
            message: CommissionDuesService::stepMessage($stage, $state['owed']),
            data: ['action' => 'commission_dues', 'salon_id' => $salon->id, 'step' => $stage],
            salon: $salon,
            dedupeKey: "commission-dues-step:{$salon->id}:{$stage}:{$state['due_date']}",
        );

        $salon->forceFill(['dues_notified_stage' => $stage, 'dues_last_reminded_at' => now()])->save();

        return true;
    }

    public function remind(Salon $salon, array $state, NotificationService $notifications, bool $manual = false): void
    {
        $amount = '₹' . number_format($state['owed'], 0);
        $due = Carbon::parse($state['due_date'])->format('j M');

        $message = $state['days_overdue'] < 0
            ? "{$amount} in commission is due by {$due}. Pay it from Payouts in the app."
            : "{$amount} in commission was due on {$due} and is still unpaid. Pay it from Payouts in the app.";

        if ($state['next']) {
            $message .= ' From ' . Carbon::parse($state['next']['on'])->format('j M') . ': ' . strtolower($state['next']['label']) . '.';
        }

        $notifications->send(
            recipient: $salon->admin_id,
            type: NotificationType::GENERAL,
            title: 'Commission payment ' . ($state['days_overdue'] < 0 ? 'due soon' : 'overdue') . ' · ' . $salon->name,
            message: $message,
            data: ['action' => 'commission_dues', 'salon_id' => $salon->id],
            salon: $salon,
            dedupeKey: $manual
                ? null
                : "commission-dues-reminder:{$salon->id}:" . Carbon::today()->toDateString(),
        );

        $salon->forceFill(['dues_last_reminded_at' => now()])->save();
    }
}
