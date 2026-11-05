<?php

namespace App\Support;

use App\Models\PlatformPolicySetting;

/**
 * SuperAdmin's two switches for what a customer pays when booking.
 *
 *  - Partial advance. On: each service (and combo) asks for its own minimum
 *    advance, a percentage of its price set by the salon; a service with none
 *    set asks for 0%. Off: no advance at all. Turning it off never touches the
 *    percentages the salons saved, so turning it back on brings them all back.
 *  - Full payment. On: the customer may choose to pay the whole bill online
 *    when booking. Always their choice, never required by this switch.
 *
 * Both are read straight from PostgreSQL (never the cache): they decide what a
 * customer is charged.
 */
final class PaymentOptions
{
    public static function partialAdvanceEnabled(): bool
    {
        return (bool) PlatformPolicySetting::value('partial_advance_enabled');
    }

    public static function fullPaymentEnabled(): bool
    {
        return (bool) PlatformPolicySetting::value('full_payment_enabled');
    }

    /**
     * The advance % a service or combo asks for, given what the salon saved.
     * Pass $partialAdvance when pricing many lines so the setting is read once.
     */
    public static function advancePercentage(mixed $saved, ?bool $partialAdvance = null): float
    {
        $partialAdvance ??= self::partialAdvanceEnabled();

        if (! $partialAdvance || $saved === null) {
            return 0.0;
        }

        return min(100.0, max(0.0, (float) $saved));
    }
}
