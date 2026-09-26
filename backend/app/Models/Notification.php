<?php

namespace App\Models;

use App\Support\Notifications\NotificationAction;
use App\Support\Notifications\NotificationType;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\UniqueConstraintViolationException;

class Notification extends Model
{
    use HasUuids;

    protected $guarded = [];

    protected $casts = [
        // The column is json; without this the payload is written as the
        // literal string "Array".
        'data' => 'array',
        'is_read' => 'boolean',
        'read_at' => 'datetime',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function appointment()
    {
        return $this->belongsTo(Appointment::class, 'related_appointment_id');
    }

    public function deliveries()
    {
        return $this->hasMany(NotificationDelivery::class);
    }

    public function getCategoryAttribute(): string
    {
        return NotificationType::categoryOf((string) $this->type);
    }

    /**
     * The action the app should route on, which is the one the payload asked
     * for and otherwise the type's default.
     *
     * Stored actions win. A notification that says "reschedule this one
     * appointment" must not be silently rewritten to "open the salon" by a
     * default that happens to match its type.
     */
    public function getActionAttribute(): ?string
    {
        $data = is_array($this->data) ? $this->data : [];

        if (isset($data['action']) && NotificationAction::isKnown((string) $data['action'])) {
            return (string) $data['action'];
        }

        return NotificationType::defaultActionFor((string) $this->type);
    }

    public function getLabelAttribute(): string
    {
        return NotificationType::labelFor((string) $this->type);
    }

    /**
     * Write a notification that is not allowed to happen twice.
     *
     * Returns null when the key has already been used, which is the answer the
     * scheduled commands want: "somebody else already sent this, carry on".
     * The unique index does the deciding, so two scheduler passes racing each
     * other still produce one notification.
     */
    public static function createOnce(array $attributes, ?string $dedupeKey = null): ?self
    {
        if ($dedupeKey !== null) {
            $attributes['dedupe_key'] = $dedupeKey;
        }

        try {
            return static::create($attributes);
        } catch (UniqueConstraintViolationException $e) {
            if ($dedupeKey === null) {
                throw $e;
            }

            return null;
        }
    }
}
