<?php

namespace App\Services\Marketing;

use Illuminate\Support\Facades\DB;

/**
 * The platform-wide marketing rules, read from the settings SuperAdmin edits.
 *
 * Every value has a working default in code. A missing row must not stop a
 * campaign — it should behave the way the platform behaved before anyone
 * thought to configure it.
 *
 * Values are cached for the life of the request because a single campaign
 * dispatch asks for the same handful of numbers once per recipient.
 */
class MarketingSettings
{
    private const DEFAULTS = [
        'marketing_inactive_customer_days' => 60,
        'marketing_repeat_customer_visits' => 3,
        'marketing_high_value_min_spend' => 5000,
        'marketing_quiet_hours_start' => 21,
        'marketing_quiet_hours_end' => 9,
        'marketing_daily_cap_per_salon' => 500,
        'marketing_require_explicit_opt_in' => 1,
    ];

    /** @var array<string, mixed>|null */
    private ?array $cache = null;

    public function inactiveDays(): int
    {
        return (int) $this->get('marketing_inactive_customer_days');
    }

    public function repeatVisits(): int
    {
        return max(2, (int) $this->get('marketing_repeat_customer_visits'));
    }

    public function highValueMinSpend(): float
    {
        return (float) $this->get('marketing_high_value_min_spend');
    }

    public function quietHoursStart(): int
    {
        return (int) $this->get('marketing_quiet_hours_start');
    }

    public function quietHoursEnd(): int
    {
        return (int) $this->get('marketing_quiet_hours_end');
    }

    public function dailyCap(): int
    {
        return (int) $this->get('marketing_daily_cap_per_salon');
    }

    public function requiresExplicitOptIn(): bool
    {
        return (bool) (int) $this->get('marketing_require_explicit_opt_in');
    }

    /**
     * Is now a reasonable hour to message somebody?
     *
     * The window wraps midnight — quiet from 21:00 to 09:00 is one period, not
     * two — so the comparison is deliberately an OR when start is later in the
     * day than end.
     */
    public function isQuietHour(?int $hour = null): bool
    {
        $hour ??= (int) now()->format('G');
        $start = $this->quietHoursStart();
        $end = $this->quietHoursEnd();

        if ($start === $end) {
            return false;
        }

        return $start > $end
            ? ($hour >= $start || $hour < $end)
            : ($hour >= $start && $hour < $end);
    }

    /** The next moment it is polite to send. */
    public function nextSendableTime(): \Illuminate\Support\Carbon
    {
        $now = now();

        if (! $this->isQuietHour()) {
            return $now;
        }

        $end = $this->quietHoursEnd();
        $candidate = $now->copy()->setTime($end, 0);

        return $candidate->lessThanOrEqualTo($now) ? $candidate->addDay() : $candidate;
    }

    private function get(string $key): mixed
    {
        if ($this->cache === null) {
            $this->cache = DB::table('platform_policy_settings')
                ->where('setting_key', 'like', 'marketing_%')
                ->pluck('setting_value', 'setting_key')
                ->all();
        }

        return $this->cache[$key] ?? self::DEFAULTS[$key] ?? 0;
    }
}
