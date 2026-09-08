<?php

namespace App\Support;

use Carbon\Carbon;

/**
 * How often a salon is settled, and where the boundaries of a cycle fall.
 *
 * A salon on a Subscription Plan has already paid, so the only money moving is
 * the advances the platform is holding — those go back weekly, because there is
 * no reason to sit on them.
 *
 * A salon on the Commission Model owes a percentage of a month's trading, and
 * that is settled monthly on the 1st for the month just finished. Charging it
 * weekly would mean billing a month in four pieces for no gain.
 */
final class PayoutCycle
{
    public const WEEKLY = 'weekly';
    public const MONTHLY = 'monthly';

    public const ALL = [self::WEEKLY, self::MONTHLY];

    /** The cycle a billing model settles on. */
    public static function forBillingModel(?string $model): string
    {
        return BillingModel::isCommission($model) ? self::MONTHLY : self::WEEKLY;
    }

    /**
     * The cycle containing $date.
     *
     * @return array{0: Carbon, 1: Carbon} start and end, inclusive
     */
    public static function bounds(string $cycleType, Carbon $date): array
    {
        return $cycleType === self::MONTHLY
            ? [$date->copy()->startOfMonth(), $date->copy()->endOfMonth()->startOfDay()]
            : [$date->copy()->startOfWeek(), $date->copy()->endOfWeek()->startOfDay()];
    }

    /**
     * The cycle that has just finished and is therefore ready to settle.
     *
     * Run on the 1st, the monthly cycle due is the month just gone; run on a
     * Monday, the weekly cycle due is last week.
     *
     * @return array{0: Carbon, 1: Carbon}
     */
    public static function previousBounds(string $cycleType, ?Carbon $on = null): array
    {
        $anchor = ($on ?? Carbon::today())->copy();

        return self::bounds(
            $cycleType,
            $cycleType === self::MONTHLY ? $anchor->subMonthNoOverflow() : $anchor->subWeek()
        );
    }

    /** How a cycle should read in a list. */
    public static function label(string $cycleType, Carbon $start, Carbon $end): string
    {
        return $cycleType === self::MONTHLY
            ? $start->format('F Y')
            : $start->format('j M') . ' – ' . $end->format('j M Y');
    }
}
