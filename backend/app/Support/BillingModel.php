<?php

namespace App\Support;

/**
 * The two ways a salon pays to trade on the platform.
 *
 * Every surface — the API, the partner app, the SuperAdmin dashboard — uses
 * these two words and no others. The platform used to store "flat" for the
 * prepaid arrangement, which told a reader nothing about what it was.
 */
final class BillingModel
{
    /** Prepaid. The salon buys a plan up front and it expires. */
    public const SUBSCRIPTION = 'subscription';

    /** Postpaid. The platform keeps a percentage, settled monthly. */
    public const COMMISSION = 'commission';

    public const ALL = [self::SUBSCRIPTION, self::COMMISSION];

    /** What a person should see. */
    public static function label(?string $model): string
    {
        return match ($model) {
            self::COMMISSION => 'Commission Model',
            self::SUBSCRIPTION => 'Subscription Plan',
            default => 'Subscription Plan',
        };
    }

    /** For request validation. */
    public static function rule(): string
    {
        return 'in:' . implode(',', self::ALL);
    }

    public static function isCommission(?string $model): bool
    {
        return $model === self::COMMISSION;
    }

    /**
     * Anything unrecognised — including the retired "flat" — reads as the
     * prepaid arrangement, which is what it always meant.
     */
    public static function normalise(?string $model): string
    {
        return self::isCommission($model) ? self::COMMISSION : self::SUBSCRIPTION;
    }
}
