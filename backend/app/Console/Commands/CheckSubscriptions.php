<?php

namespace App\Console\Commands;

use App\Models\Notification;
use App\Models\PlatformPolicySetting;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Services\Notifications\NotificationService;
use App\Services\SalonAccessService;
use Carbon\Carbon;
use Illuminate\Console\Command;

/**
 * Keeps subscription state honest and chases owners to renew.
 *
 * Runs hourly. Expiring lapsed plans happens on every pass so nothing is a day
 * stale; the reminders only go out once, at the hour SuperAdmin has configured,
 * because a renewal nudge at 3am converts nobody.
 */
class CheckSubscriptions extends Command
{
    protected $signature = 'app:check-subscriptions {--force-reminders : Send reminders regardless of the configured hour}';

    protected $description = 'Expire lapsed subscriptions and remind salon owners to renew';

    /** Notification types, so the app can route a tap to the renewal screen. */
    public const TYPE_EXPIRING = 'subscription_expiring';
    public const TYPE_EXPIRED = 'subscription_expired';

    /**
     * The same lapse, told to the collaborator who set the salon up.
     *
     * Kept as its own type because the two audiences can do different things
     * about it: the owner can pay, the collaborator can only pick up the phone.
     * Routing a collaborator to a renewal screen would be a dead end.
     */
    public const TYPE_ASSIGNED_EXPIRING = 'assigned_salon_expiring';

    /**
     * How far ahead of expiry the collaborator who onboarded the salon hears
     * about it, in days, as [ 'the early warning', 'the last call' ].
     *
     * Two rungs rather than one, because the collaborator's only lever is a
     * phone call and the two ends of that window behave differently. At seven
     * days the owner has not yet decided the renewal is not worth it and a call
     * still lands. By three days most have decided, and the call is not about
     * persuading them — it is about finding out whether they noticed at all
     * before the salon goes dark.
     *
     * Descending. [rungFor] walks this to work out which window a given number
     * of days falls into.
     */
    private const COLLABORATOR_WARNING_LADDER = [7, 3];

    public function handle(SalonAccessService $access, NotificationService $notifications): int
    {
        $expired = $access->expireStale();
        $this->info("Expired {$expired} subscription(s).");

        if (! $this->option('force-reminders') && ! $this->isReminderHour()) {
            $this->info('Not the reminder hour; skipping notifications.');

            return self::SUCCESS;
        }

        $this->info('Sending renewal reminders…');
        $this->remindExpiring($notifications);
        $this->remindLapsed($notifications);

        return self::SUCCESS;
    }

    /**
     * Owners are at the salon and not yet busy at mid-morning, which is when a
     * renewal actually gets acted on rather than dismissed.
     */
    private function isReminderHour(): bool
    {
        $hour = (int) PlatformPolicySetting::value('subscription_reminder_hour');

        return now()->hour === $hour;
    }

    /**
     * A heads-up while the plan is still running.
     *
     * Two audiences leave this loop with different horizons. The owner's window
     * is whatever SuperAdmin configured, unchanged. The collaborator's is the
     * longer ladder above, because the call has to be made early enough to
     * still be worth making — which is why the query reaches past the owner's
     * window while the owner's own reminder does not.
     */
    private function remindExpiring(NotificationService $notifications): void
    {
        $ownerWarningDays = (int) PlatformPolicySetting::value('subscription_expiry_warning_days');
        $reach = max(self::COLLABORATOR_WARNING_LADDER[0], $ownerWarningDays);

        $expiring = SalonSubscription::with('salon.admin')
            ->where('status', 'active')
            ->whereDate('end_date', '<=', now()->addDays($reach)->toDateString())
            ->whereDate('end_date', '>=', now()->toDateString())
            ->get();

        foreach ($expiring as $subscription) {
            $salon = $subscription->salon;

            if (! $salon) {
                continue;
            }

            $daysLeft = (int) Carbon::today()->diffInDays(Carbon::parse($subscription->end_date), false);

            // Gated on the owner's own window, not on the query's reach: widening
            // the loop above is for the collaborator, and must not pull the
            // owner's inbox into the seven-day rung they were never shown.
            if ($salon->admin_id && $daysLeft <= $ownerWarningDays) {
                $this->notifyOnce($salon->admin_id, $salon, self::TYPE_EXPIRING, [
                    'title' => $daysLeft <= 0
                        ? 'Your plan ends today'
                        : "Your plan ends in {$daysLeft} day" . ($daysLeft === 1 ? '' : 's'),
                    'message' => sprintf(
                        '%s stops taking online bookings when the plan ends. Renew now to stay listed.',
                        $salon->name
                    ),
                ], ['action' => 'renew_subscription', 'salon_id' => $salon->id]);
            }

            $rung = $this->rungFor($daysLeft);

            if ($rung !== null) {
                $this->alertCollaborator(
                    $notifications,
                    $salon,
                    $daysLeft,
                    "assigned_salon_expiring:{$salon->id}:{$subscription->id}:w{$rung}",
                    $rung
                );
            }
        }
    }

    /**
     * Which rung of [COLLABORATOR_WARNING_LADDER] owns this many days left, or
     * null when the number has fallen past all of them.
     *
     * A window rather than an exact day, and that is the whole point. This runs
     * hourly but only fires at one configured hour, so demanding that days left
     * be exactly 7 would mean a host that was down yesterday never gets a
     * collaborator told anything at all. Each rung owns the span from itself
     * down to just above the next one: 7 owns 7,6,5,4 and 3 owns 3,2,1,0.
     */
    private function rungFor(int $daysLeft): ?int
    {
        foreach (self::COLLABORATOR_WARNING_LADDER as $index => $rung) {
            $floor = self::COLLABORATOR_WARNING_LADDER[$index + 1] ?? -1;

            if ($daysLeft <= $rung && $daysLeft > $floor) {
                return $rung;
            }
        }

        return null;
    }

    /**
     * Tell the collaborator who onboarded this salon that it is about to go
     * quiet.
     *
     * They have the owner's number, which makes them the cheapest possible
     * save. Covers both salons they onboarded and ones SuperAdmin handed them
     * from the directory — the responsibility is the same either way.
     *
     * Goes through [NotificationService] rather than writing the row here, which
     * is what makes this reach their phone and not just their inbox. The dedupe
     * key carries the subscription, so a salon that renews and later runs down
     * again gets a fresh pair of warnings instead of being permanently muted by
     * the last plan's keys.
     */
    private function alertCollaborator(
        NotificationService $notifications,
        Salon $salon,
        int $daysLeft,
        string $dedupeKey,
        ?int $rung = null
    ): void {
        $notification = $notifications->assignedSalonExpiring($salon, $daysLeft, $dedupeKey);

        if ($notification) {
            $window = $rung !== null ? ", rung {$rung}" : '';
            $this->info("Told the collaborator about {$salon->name} ({$daysLeft} day(s) left{$window}).");
        }
    }

    /**
     * The daily nudge after it has lapsed. Sent every day until they renew,
     * because the salon is invisible to customers the whole time.
     */
    private function remindLapsed(NotificationService $notifications): void
    {
        $lapsed = Salon::with('admin')
            ->where('status', 'active')
            ->whereDoesntHave('subscriptions', fn ($q) => $q->where('status', 'active'))
            ->get();

        foreach ($lapsed as $salon) {
            if (! $salon->admin_id) {
                continue;
            }

            $last = SalonSubscription::where('salon_id', $salon->id)
                ->orderByDesc('end_date')
                ->first();

            // Never subscribed at all — that is onboarding, not a renewal.
            if (! $last) {
                continue;
            }

            $daysDown = (int) Carbon::parse($last->end_date)->diffInDays(Carbon::today());

            $this->notifyOnce($salon->admin_id, $salon, self::TYPE_EXPIRED, [
                'title' => 'Your salon is offline',
                'message' => sprintf(
                    '%s has been hidden from customers for %s. Your staff cannot use the app either. Renew to go back online.',
                    $salon->name,
                    $daysDown <= 1 ? 'a day' : "{$daysDown} days"
                ),
            ], ['action' => 'renew_subscription', 'salon_id' => $salon->id]);

            $this->alertCollaborator(
                $notifications,
                $salon,
                -$daysDown,
                // There is no active subscription left to key on, and the nudge is
                // meant to repeat daily — so the day is the unit, not the plan.
                "assigned_salon_expiring:{$salon->id}:lapsed:".Carbon::today()->toDateString()
            );
        }
    }

    /**
     * One reminder per recipient per salon per day. Re-running the command must
     * not stack up duplicates in anybody's inbox.
     */
    private function notifyOnce(?string $userId, Salon $salon, string $type, array $content, array $data): void
    {
        if (! $userId) {
            return;
        }

        $alreadySentToday = Notification::where('user_id', $userId)
            ->where('type', $type)
            ->where('related_salon_id', $salon->id)
            ->whereDate('created_at', Carbon::today())
            ->exists();

        if ($alreadySentToday) {
            return;
        }

        Notification::create([
            'user_id' => $userId,
            'type' => $type,
            'title' => $content['title'],
            'message' => $content['message'],
            'data' => $data,
            'related_salon_id' => $salon->id,
            'is_read' => false,
        ]);

        $this->info("Reminded {$salon->name} ({$type}).");
    }
}
