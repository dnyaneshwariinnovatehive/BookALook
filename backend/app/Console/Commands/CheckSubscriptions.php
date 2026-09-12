<?php

namespace App\Console\Commands;

use App\Models\Notification;
use App\Models\PlatformPolicySetting;
use App\Models\Salon;
use App\Models\SalonSubscription;
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

    public function handle(SalonAccessService $access): int
    {
        $expired = $access->expireStale();
        $this->info("Expired {$expired} subscription(s).");

        if (! $this->option('force-reminders') && ! $this->isReminderHour()) {
            $this->info('Not the reminder hour; skipping notifications.');

            return self::SUCCESS;
        }

        $this->info('Sending renewal reminders…');
        $this->remindExpiring();
        $this->remindLapsed();

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
     */
    private function remindExpiring(): void
    {
        $warningDays = (int) PlatformPolicySetting::value('subscription_expiry_warning_days');

        $expiring = SalonSubscription::with('salon.admin')
            ->where('status', 'active')
            ->whereDate('end_date', '<=', now()->addDays($warningDays)->toDateString())
            ->whereDate('end_date', '>=', now()->toDateString())
            ->get();

        foreach ($expiring as $subscription) {
            $salon = $subscription->salon;

            if (! $salon?->admin_id) {
                continue;
            }

            $daysLeft = (int) Carbon::today()->diffInDays(Carbon::parse($subscription->end_date), false);

            $this->notifyOnce($salon->admin_id, $salon, self::TYPE_EXPIRING, [
                'title' => $daysLeft <= 0
                    ? 'Your plan ends today'
                    : "Your plan ends in {$daysLeft} day" . ($daysLeft === 1 ? '' : 's'),
                'message' => sprintf(
                    '%s stops taking online bookings when the plan ends. Renew now to stay listed.',
                    $salon->name
                ),
            ], ['action' => 'renew_subscription', 'salon_id' => $salon->id]);

            $this->alertCollaborator($salon, $daysLeft);
        }
    }

    /**
     * Tell the collaborator who onboarded this salon that it is about to go
     * quiet.
     *
     * They have the owner's number, which makes them the cheapest possible
     * save. Covers both salons they onboarded and ones SuperAdmin handed them
     * from the directory — the responsibility is the same either way.
     */
    private function alertCollaborator(Salon $salon, int $daysLeft): void
    {
        if (! $salon->assigned_collaborator_id) {
            return;
        }

        $when = match (true) {
            $daysLeft <= 0 => 'today',
            $daysLeft === 1 => 'tomorrow',
            default => "in {$daysLeft} days",
        };

        $this->notifyOnce($salon->assigned_collaborator_id, $salon, self::TYPE_ASSIGNED_EXPIRING, [
            'title' => "{$salon->name}'s plan ends {$when}",
            'message' => sprintf(
                'A salon you onboarded is about to stop taking bookings. Give %s a call '
                . 'before it goes offline.',
                $salon->admin->name ?? 'the owner'
            ),
        ], [
            // No renewal action: a collaborator cannot pay for someone else's
            // salon, so the only useful thing to offer is the phone number.
            'action' => 'call_owner',
            'salon_id' => $salon->id,
            'owner_phone' => $salon->admin->phone ?? null,
        ]);
    }

    /**
     * The daily nudge after it has lapsed. Sent every day until they renew,
     * because the salon is invisible to customers the whole time.
     */
    private function remindLapsed(): void
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

            $this->alertCollaborator($salon, -$daysDown);
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
