<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One notification, one destination, one outcome.
 *
 * The notification row says what the customer was told; this row says whether
 * the phone actually got it. Both are needed, because "we wrote a row" and "the
 * message arrived" are separate claims and only the second one is worth
 * anything to a customer waiting on a reschedule link.
 */
class NotificationDelivery extends Model
{
    use HasUuids;

    public const CHANNEL_PUSH = 'push';

    public const STATUS_PENDING = 'pending';
    public const STATUS_SENT = 'sent';
    public const STATUS_FAILED = 'failed';

    protected $guarded = [];

    protected $casts = [
        'attempt_count' => 'integer',
        'sent_at' => 'datetime',
        'delivered_at' => 'datetime',
        'failed_at' => 'datetime',
    ];

    public function notification(): BelongsTo
    {
        return $this->belongsTo(Notification::class);
    }

    public function userDevice(): BelongsTo
    {
        return $this->belongsTo(UserDevice::class);
    }

    public function scopeUnfinished($query)
    {
        return $query->where('status', self::STATUS_PENDING);
    }

    public function scopeFailed($query)
    {
        return $query->where('status', self::STATUS_FAILED);
    }

    /**
     * The attempt count after one more try, without clobbering the attempts
     * already recorded.
     *
     * Shared by the first send and every retry so the number means the same
     * thing in both places. A device that was rate-limited on the original send
     * and then on two retries should read 3, not 1: the field exists to answer
     * "how hard did we try", and a retry that overwrote it with 1 would make a
     * repeated failure look like a first one.
     */
    public function countAttempt(int $times = 1): int
    {
        return max(1, (int) $this->attempt_count) + max(1, $times);
    }
}
