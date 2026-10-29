<?php

namespace App\Services;

use App\Models\PayoutPaymentSubmission;
use App\Models\PlatformPolicySetting;
use App\Models\Salon;
use App\Models\SalonPayout;
use Carbon\Carbon;
use Illuminate\Support\Collection;

/**
 * What a Commission Model salon owes BookALook, how late it is, and what
 * that means for the salon right now.
 *
 * SuperAdmin sets a ladder in Policy: a due date (days after the month
 * closes), a floor below which nothing happens, and a list of steps, each
 * switched on or off and each starting so many days after the due date:
 *
 *   reminder → banner → force full advance → deduct from payouts
 *            → stop new online bookings → full lock
 *
 * Every step is worked out from the unpaid dues on read, so the moment the
 * salon pays (or its dues are recovered) everything lifts by itself. On top
 * of the schedule SuperAdmin can, per salon, push the due date out, pause the
 * steps, or apply a step by hand.
 *
 * Dues are payouts where the salon owes BookALook (a negative net), not yet
 * settled, for cycles that have closed. A payout with payment proof waiting to
 * be verified is left out: the salon has done its part.
 */
class CommissionDuesService
{
    public const STEP_REMINDER = 'reminder';
    public const STEP_BANNER = 'banner';
    public const STEP_FORCE_ADVANCE = 'force_advance';
    public const STEP_DEDUCT = 'deduct';
    public const STEP_STOP_BOOKINGS = 'stop_bookings';
    public const STEP_FULL_LOCK = 'full_lock';

    /** Mildest first. Order matters: a manual stage applies everything up to it. */
    public const STEPS = [
        self::STEP_REMINDER,
        self::STEP_BANNER,
        self::STEP_FORCE_ADVANCE,
        self::STEP_DEDUCT,
        self::STEP_STOP_BOOKINGS,
        self::STEP_FULL_LOCK,
    ];

    public const LABELS = [
        self::STEP_REMINDER => 'Reminders',
        self::STEP_BANNER => 'Warning banner',
        self::STEP_FORCE_ADVANCE => 'Full payment online',
        self::STEP_DEDUCT => 'Deduct from payouts',
        self::STEP_STOP_BOOKINGS => 'New online bookings stopped',
        self::STEP_FULL_LOCK => 'Full lock',
    ];

    /** Manual stage: none of the steps, whatever the schedule says. */
    public const OVERRIDE_NONE = 'none';

    /** The policy keys, and their defaults. */
    public const SETTINGS = [
        'commission_dues_min_amount' => 200,
        'commission_dues_reminder_enabled' => true,
        'commission_dues_reminder_before_days' => 3,
        'commission_dues_reminder_every_days' => 3,
        'commission_dues_banner_enabled' => true,
        'commission_dues_banner_days' => 0,
        'commission_dues_force_advance_enabled' => true,
        'commission_dues_force_advance_days' => 3,
        'commission_dues_deduct_enabled' => true,
        'commission_dues_deduct_days' => 3,
        'commission_dues_stop_bookings_enabled' => true,
        'commission_dues_stop_bookings_days' => 10,
        'commission_dues_full_lock_enabled' => true,
        'commission_dues_full_lock_days' => 20,
    ];

    /**
     * The ladder as SuperAdmin set it.
     *
     * @return array{grace_days: int, min_amount: float, reminder_before_days: int, reminder_every_days: int, steps: array<string, array{enabled: bool, days: int}>}
     */
    public function settings(): array
    {
        // One query for the lot: this runs for every commission salon in a
        // directory listing.
        $keys = array_merge(array_keys(self::SETTINGS), [CommissionService::GRACE_DAYS_KEY]);
        $rows = PlatformPolicySetting::whereIn('setting_key', $keys)->get()->keyBy('setting_key');
        $v = function (string $key) use ($rows) {
            $row = $rows->get($key);
            if (! $row) {
                return PlatformPolicySetting::DEFAULTS[$key] ?? self::SETTINGS[$key] ?? null;
            }

            return match ($row->data_type) {
                'integer' => (int) $row->setting_value,
                'decimal' => (float) $row->setting_value,
                'boolean' => filter_var($row->setting_value, FILTER_VALIDATE_BOOLEAN),
                default => $row->setting_value,
            };
        };
        $steps = [];
        foreach (self::STEPS as $step) {
            $steps[$step] = [
                'enabled' => (bool) $v("commission_dues_{$step}_enabled"),
                // Reminders start before the due date and are configured apart.
                'days' => $step === self::STEP_REMINDER
                    ? -(int) $v('commission_dues_reminder_before_days')
                    : (int) $v("commission_dues_{$step}_days"),
            ];
        }

        return [
            'grace_days' => (int) $v(CommissionService::GRACE_DAYS_KEY),
            'min_amount' => (float) $v('commission_dues_min_amount'),
            'reminder_before_days' => (int) $v('commission_dues_reminder_before_days'),
            'reminder_every_days' => (int) $v('commission_dues_reminder_every_days'),
            'steps' => $steps,
        ];
    }

    /**
     * Payouts the salon still owes on, oldest first.
     *
     * @return Collection<int, SalonPayout>
     */
    public function owedPayouts(string $salonId): Collection
    {
        return SalonPayout::with('paymentSubmissions')
            ->where('salon_id', $salonId)
            ->whereIn('status', [PayoutService::STATUS_PENDING, PayoutService::STATUS_APPROVED])
            ->where('net_amount', '<', 0)
            ->orderBy('cycle_start_date')
            ->get()
            ->reject(fn (SalonPayout $p) => PayoutService::cycleInProgress($p))
            ->values();
    }

    /**
     * Where the salon stands. Never throws; a salon with nothing owed, or not
     * on the Commission Model, comes back with no steps.
     *
     * @return array<string, mixed>
     */
    public function state(Salon $salon, ?array $settings = null): array
    {
        $settings ??= $this->settings();
        $today = Carbon::today();

        $base = [
            'applies' => false,
            'owed' => 0.0,
            'payouts' => 0,
            'under_review' => 0,
            'oldest_cycle_end' => null,
            'due_date' => null,
            'scheduled_due_date' => null,
            'days_overdue' => null,
            'actions' => [],
            'stage' => null,
            'next' => null,
            'paused' => (bool) $salon->dues_paused,
            'extended_until' => $salon->dues_extended_until ? Carbon::parse($salon->dues_extended_until)->toDateString() : null,
            'override' => $salon->dues_stage_override,
            'override_reason' => $salon->dues_override_reason,
            'below_minimum' => false,
        ];

        if (! $salon->isOnCommissionModel()) {
            return $base;
        }

        $owed = $this->owedPayouts($salon->id);
        $reviewing = $owed->filter(fn (SalonPayout $p) => $p->paymentSubmissions
            ->contains('status', PayoutPaymentSubmission::STATUS_PENDING));
        $chasing = $owed->diff($reviewing)->values();

        $amount = round(abs((float) $chasing->sum('net_amount')), 2);
        $base['under_review'] = $reviewing->count();

        if ($chasing->isEmpty()) {
            return $base;
        }

        $oldestEnd = Carbon::parse($chasing->first()->cycle_end_date)->startOfDay();
        $scheduled = $oldestEnd->copy()->addDays($settings['grace_days']);
        $due = $scheduled->copy();
        if ($salon->dues_extended_until && Carbon::parse($salon->dues_extended_until)->gt($due)) {
            $due = Carbon::parse($salon->dues_extended_until)->startOfDay();
        }
        $daysOverdue = (int) $due->diffInDays($today, false);

        $state = array_merge($base, [
            'applies' => true,
            'owed' => $amount,
            'payouts' => $chasing->count(),
            'oldest_cycle_end' => $oldestEnd->toDateString(),
            'due_date' => $due->toDateString(),
            'scheduled_due_date' => $scheduled->toDateString(),
            'days_overdue' => $daysOverdue,
            'below_minimum' => $amount < $settings['min_amount'],
        ]);

        if ($state['below_minimum'] || $state['paused']) {
            return $state;
        }

        $actions = $this->actionsFor($daysOverdue, $settings, $salon->dues_stage_override);
        $state['actions'] = $actions;
        $state['stage'] = $actions === [] ? null : end($actions);
        $state['next'] = $salon->dues_stage_override ? null : $this->nextStep($daysOverdue, $due, $settings);

        return $state;
    }

    /** Whether a step is in force for this salon right now. */
    public function has(Salon $salon, string $step): bool
    {
        if (! $salon->isOnCommissionModel()) {
            return false;
        }

        return in_array($step, $this->state($salon)['actions'], true);
    }

    /**
     * The steps in force at this many days past due.
     *
     * @return array<int, string>
     */
    public function actionsFor(int $daysOverdue, array $settings, ?string $override = null): array
    {
        if ($override === self::OVERRIDE_NONE) {
            return [];
        }

        if ($override && in_array($override, self::STEPS, true)) {
            $limit = array_search($override, self::STEPS, true);

            // Everything switched on up to the chosen step, and the chosen step
            // itself even if the schedule has it off — SuperAdmin asked for it.
            return array_values(array_filter(
                self::STEPS,
                fn ($step, $i) => $i <= $limit && ($settings['steps'][$step]['enabled'] || $step === $override),
                ARRAY_FILTER_USE_BOTH,
            ));
        }

        return array_values(array_filter(
            self::STEPS,
            fn ($step) => $settings['steps'][$step]['enabled'] && $daysOverdue >= $settings['steps'][$step]['days'],
        ));
    }

    /** The next step the schedule will add, and the day it starts. */
    private function nextStep(int $daysOverdue, Carbon $due, array $settings): ?array
    {
        $upcoming = collect(self::STEPS)
            ->filter(fn ($step) => $settings['steps'][$step]['enabled'] && $settings['steps'][$step]['days'] > $daysOverdue)
            ->sortBy(fn ($step) => $settings['steps'][$step]['days'])
            ->first();

        return $upcoming ? [
            'step' => $upcoming,
            'label' => self::LABELS[$upcoming],
            'on' => $due->copy()->addDays($settings['steps'][$upcoming]['days'])->toDateString(),
        ] : null;
    }

    /**
     * Whether today is a reminder day: the first one so many days before the
     * due date, then every so many days after that.
     */
    public function isReminderDay(array $state, array $settings): bool
    {
        if (! in_array(self::STEP_REMINDER, $state['actions'], true) || $state['days_overdue'] === null) {
            return false;
        }

        $since = $state['days_overdue'] + $settings['reminder_before_days'];
        $every = max(0, $settings['reminder_every_days']);

        return $since === 0 || ($every > 0 && $since > 0 && $since % $every === 0);
    }

    /** What the owner is told when a step starts. */
    public static function stepMessage(string $step, float $owed): string
    {
        $amount = '₹' . number_format($owed, 0);

        return match ($step) {
            self::STEP_BANNER => "{$amount} in commission is now overdue. Please pay it to avoid restrictions.",
            self::STEP_FORCE_ADVANCE => "{$amount} is overdue, so customers now pay the full amount online when they book.",
            self::STEP_DEDUCT => "{$amount} is overdue, so it will be deducted from the money BookALook pays you.",
            self::STEP_STOP_BOOKINGS => "New online bookings are paused until the overdue {$amount} is paid. Existing bookings are not affected.",
            self::STEP_FULL_LOCK => "The salon is locked until the overdue {$amount} is paid.",
            default => "{$amount} in commission is due. Please pay it from Payouts in the app.",
        };
    }
}
