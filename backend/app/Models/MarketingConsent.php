<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Whether a number may be marketed to.
 *
 * Keyed on the phone, not the user. A walk-in customer is a name and a number
 * written on an appointment with no account behind it, and someone who replies
 * STOP has to stay stopped whether or not they ever sign up — the wish belongs
 * to the number.
 *
 * Opting out is one-way here. Nothing in the platform flips a number back to
 * opted-in; only the person can, by writing in again.
 */
class MarketingConsent extends Model
{
    use HasUuids;

    protected $fillable = [
        'phone',
        'user_id',
        'status',
        'source',
        'opted_in_at',
        'opted_out_at',
    ];

    protected $casts = [
        'opted_in_at' => 'datetime',
        'opted_out_at' => 'datetime',
    ];

    public const STATUS_IN = 'opted_in';
    public const STATUS_OUT = 'opted_out';

    public const SOURCE_BOOKING = 'booking';
    public const SOURCE_REPLY = 'reply';
    public const SOURCE_ADMIN = 'admin';
    public const SOURCE_IMPORT = 'import';

    /**
     * Record that a number asked to be left alone.
     *
     * Called from the inbound webhook when someone replies STOP. It must work
     * for a number nobody has a record of, because the reply itself may be the
     * first thing the platform ever hears from them.
     */
    public static function optOut(string $phone, string $source = self::SOURCE_REPLY): self
    {
        $consent = static::firstOrNew(['phone' => $phone]);

        $consent->fill([
            'status' => self::STATUS_OUT,
            'source' => $source,
            'opted_out_at' => now(),
        ])->save();

        return $consent;
    }

    public static function optIn(string $phone, ?string $userId = null, string $source = self::SOURCE_BOOKING): ?self
    {
        $consent = static::firstOrNew(['phone' => $phone]);

        // Someone who has opted out stays opted out. Booking again is not
        // permission to resume marketing at them.
        if ($consent->exists && $consent->status === self::STATUS_OUT) {
            return $consent;
        }

        $consent->fill([
            'user_id' => $userId ?? $consent->user_id,
            'status' => self::STATUS_IN,
            'source' => $source,
            'opted_in_at' => $consent->opted_in_at ?? now(),
        ])->save();

        return $consent;
    }

    public function scopeOptedOut($query)
    {
        return $query->where('status', self::STATUS_OUT);
    }
}
