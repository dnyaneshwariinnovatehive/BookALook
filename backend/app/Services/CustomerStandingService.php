<?php

namespace App\Services;

use App\Models\Appointment;
use App\Models\PlatformPolicySetting;
use App\Models\User;
use Carbon\Carbon;

/**
 * How many times a customer may cancel, or not turn up, before booking is
 * restricted — one rule for every customer, set by SuperAdmin, counted across
 * the whole platform.
 *
 *  - Cancellations are the customer's own; a salon or the system cancelling
 *    never counts against them.
 *  - "Consecutive" counts the current run: a completed visit starts it again.
 *    "In total" counts every one inside the look-back window.
 *  - What happens at the limit is SuperAdmin's choice: block booking, require
 *    the full amount upfront, or only warn. Blocking exists so the limit still
 *    means something with online payments switched off.
 *  - A restriction lifts by itself a set number of days after the last
 *    offence, or only when SuperAdmin clears the customer's record.
 */
class CustomerStandingService
{
    public const ACTION_BLOCK = 'block';
    public const ACTION_FULL_PAYMENT = 'full_payment';
    public const ACTION_WARN = 'warn';
    public const ACTIONS = [self::ACTION_BLOCK, self::ACTION_FULL_PAYMENT, self::ACTION_WARN];

    public const MODE_CONSECUTIVE = 'consecutive';
    public const MODE_TOTAL = 'total';
    public const MODES = [self::MODE_CONSECUTIVE, self::MODE_TOTAL];

    /** The settings, with their defaults (limits of 0 mean "no limit"). */
    public const DEFAULTS = [
        'customer_cancellation_limit' => 0,
        'customer_cancellation_count_mode' => self::MODE_TOTAL,
        'customer_no_show_limit' => 0,
        'customer_no_show_count_mode' => self::MODE_TOTAL,
        'customer_limit_action' => self::ACTION_BLOCK,
        // How far back "in total" looks. 0 = for ever.
        'customer_limit_window_days' => 90,
        // Days after the last offence the restriction lifts. 0 = SuperAdmin only.
        'customer_limit_release_days' => 30,
    ];

    /** @return array<string, int|string> */
    public function settings(): array
    {
        $out = [];
        foreach (self::DEFAULTS as $key => $default) {
            $out[$key] = PlatformPolicySetting::value($key, $default);
        }

        return $out;
    }

    /**
     * A customer's record against the limits, and whether booking is affected.
     *
     * @return array{
     *   restricted: bool, action: ?string, message: ?string, releases_on: ?string,
     *   cancellations: array{count: int, limit: int, mode: string, reached: bool},
     *   no_shows: array{count: int, limit: int, mode: string, reached: bool}
     * }
     */
    public function standing(User $customer): array
    {
        $s = $this->settings();
        $events = $this->events($customer, (int) $s['customer_limit_window_days']);

        $cancel = $this->measure($events, 'cancelled', (int) $s['customer_cancellation_limit'], (string) $s['customer_cancellation_count_mode'], (int) $s['customer_limit_release_days']);
        $noShow = $this->measure($events, 'no_show', (int) $s['customer_no_show_limit'], (string) $s['customer_no_show_count_mode'], (int) $s['customer_limit_release_days']);

        $restricted = $cancel['reached'] || $noShow['reached'];
        $action = $restricted ? (string) $s['customer_limit_action'] : null;

        $releases = collect([$cancel['releases_on'], $noShow['releases_on']])->filter()->sort()->last();

        return [
            'restricted' => $restricted,
            'action' => $action,
            'message' => $restricted ? $this->message($action, $cancel, $noShow, $releases) : null,
            'releases_on' => $restricted ? $releases : null,
            'cancellations' => array_diff_key($cancel, ['releases_on' => 1]),
            'no_shows' => array_diff_key($noShow, ['releases_on' => 1]),
        ];
    }

    /** Clear the customer's record: only what happens from now counts. */
    public function reset(User $customer): void
    {
        $customer->forceFill(['booking_standing_reset_at' => now()])->save();
    }

    /**
     * Completed visits, the customer's own cancellations and no-shows, newest
     * first — the only outcomes that move the count.
     */
    private function events(User $customer, int $windowDays)
    {
        $reset = $customer->booking_standing_reset_at ? Carbon::parse($customer->booking_standing_reset_at) : null;

        return Appointment::query()
            ->where('customer_id', $customer->id)
            ->where(function ($q) {
                $q->whereIn('status', ['completed', 'no_show'])
                    ->orWhere(fn ($c) => $c->where('status', 'cancelled')->where('cancelled_by', 'customer'));
            })
            ->when($windowDays > 0, fn ($q) => $q->whereDate('appointment_date', '>=', Carbon::today()->subDays($windowDays)->toDateString()))
            ->when($reset, fn ($q) => $q->where(function ($r) use ($reset) {
                $r->whereDate('appointment_date', '>', $reset->toDateString())
                    ->orWhere('updated_at', '>', $reset);
            }))
            ->orderByDesc('appointment_date')
            ->orderByDesc('start_time')
            ->get(['id', 'status', 'appointment_date', 'cancelled_at', 'updated_at']);
    }

    /**
     * One limit against the events.
     *
     * @return array{count: int, limit: int, mode: string, reached: bool, releases_on: ?string}
     */
    private function measure($events, string $status, int $limit, string $mode, int $releaseDays): array
    {
        $count = 0;
        $latest = null;

        foreach ($events as $event) {
            if ($mode === self::MODE_CONSECUTIVE && $event->status === 'completed') {
                break; // a visit that happened ends the run
            }
            if ($event->status === $status) {
                $count++;
                $when = Carbon::parse($event->cancelled_at ?? $event->appointment_date);
                $latest = $latest && $latest->gt($when) ? $latest : $when;
            }
        }

        $reached = $limit > 0 && $count >= $limit;
        $releasesOn = null;

        if ($reached && $releaseDays > 0 && $latest) {
            $release = $latest->copy()->startOfDay()->addDays($releaseDays);
            if ($release->lte(Carbon::today())) {
                $reached = false; // served its time
            } else {
                $releasesOn = $release->toDateString();
            }
        }

        return ['count' => $count, 'limit' => $limit, 'mode' => $mode, 'reached' => $reached, 'releases_on' => $releasesOn];
    }

    private function message(?string $action, array $cancel, array $noShow, ?string $releases): string
    {
        $what = collect([
            $cancel['reached'] ? "{$cancel['count']} cancellation" . ($cancel['count'] === 1 ? '' : 's') : null,
            $noShow['reached'] ? "{$noShow['count']} missed appointment" . ($noShow['count'] === 1 ? '' : 's') : null,
        ])->filter()->implode(' and ');

        $until = $releases ? ' until ' . Carbon::parse($releases)->format('j M Y') : '';

        return match ($action) {
            self::ACTION_BLOCK => "You have {$what}, so new bookings are paused{$until}. Please contact BookALook support if you think this is a mistake.",
            self::ACTION_FULL_PAYMENT => "You have {$what}, so new bookings need the full amount paid upfront{$until}.",
            default => "You have {$what}. Further cancellations or missed appointments may restrict your bookings.",
        };
    }
}
