<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

/**
 * A customer reporting a salon to the platform.
 *
 * Deliberately not the same thing as a bad review. A review is public and the
 * salon lives with it; a complaint is private, goes straight to SuperAdmin, and
 * can end with the salon warned or taken offline. Keeping them apart means a
 * customer can say "three stars, the cut was rushed" without escalating, and
 * can escalate without having to leave a public review at all.
 */
class Complaint extends Model
{
    use HasUuids;

    /** Nobody has looked at it yet. */
    public const STATUS_OPEN = 'open';

    /** SuperAdmin has picked it up but has not decided. */
    public const STATUS_UNDER_REVIEW = 'under_review';

    /** Acted on — see action_taken for what was actually done. */
    public const STATUS_RESOLVED = 'resolved';

    /** Looked at and judged not to need action. */
    public const STATUS_DISMISSED = 'dismissed';

    /** The salon's owner was sent a written warning. */
    public const ACTION_WARNING = 'warning';

    /** The salon was taken offline. */
    public const ACTION_SUSPENDED = 'suspended';

    /** Nothing was wrong, or nothing could be substantiated. */
    public const ACTION_DISMISSED = 'dismissed';

    protected $fillable = [
        'salon_id',
        'customer_id',
        'related_appointment_id',
        'subject',
        'description',
        'status',
        'action_taken',
        'resolution_note',
        'resolved_by',
        'resolved_at',
    ];

    protected $casts = [
        'resolved_at' => 'datetime',
    ];

    /** Still needs a decision from SuperAdmin. */
    public function scopeOutstanding($query)
    {
        return $query->whereIn('status', [self::STATUS_OPEN, self::STATUS_UNDER_REVIEW]);
    }

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }

    public function customer()
    {
        return $this->belongsTo(User::class, 'customer_id');
    }

    public function appointment()
    {
        return $this->belongsTo(Appointment::class, 'related_appointment_id');
    }

    public function resolver()
    {
        return $this->belongsTo(User::class, 'resolved_by');
    }
}
