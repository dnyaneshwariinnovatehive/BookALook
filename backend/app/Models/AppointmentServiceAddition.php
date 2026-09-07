<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class AppointmentServiceAddition extends Model
{
    use HasUuids;

    /** On the bill and still being delivered. */
    public const STATUS_ACTIVE = 'active';

    /** Delivered and settled — the mirror of a booked line's 'completed'. */
    public const STATUS_COMPLETED = 'completed';

    /** Taken back off the bill. Kept so the record can still explain itself. */
    public const STATUS_VOIDED = 'voided';

    /**
     * Everything that counts towards the bill and towards commission. A voided
     * addition is the only thing that does not.
     */
    public const LIVE_STATUSES = [self::STATUS_ACTIVE, self::STATUS_COMPLETED];

    protected $guarded = [];

    protected $casts = [
        'added_at' => 'datetime',
    ];

    /** On the bill: added and not since removed. */
    public function scopeLive($query)
    {
        return $query->whereIn('status', self::LIVE_STATUSES);
    }

    public function isLive(): bool
    {
        return in_array($this->status, self::LIVE_STATUSES, true);
    }

    public function appointment()
    {
        return $this->belongsTo(Appointment::class);
    }

    public function service()
    {
        return $this->belongsTo(Service::class);
    }

    public function provider()
    {
        return $this->belongsTo(ServiceProvider::class, 'provider_id');
    }

    public function addedBy()
    {
        return $this->belongsTo(User::class, 'added_by');
    }
}
