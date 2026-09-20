<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

/**
 * One queued or delivered WhatsApp notification. See the whatsapp_messages
 * migration for why sends are persisted rather than fired and forgotten.
 */
class WhatsAppMessage extends Model
{
    use HasUuids;

    protected $table = 'whatsapp_messages';

    protected $guarded = [];

    protected $casts = [
        'payload' => 'array',
        'sent_at' => 'datetime',
        'delivered_at' => 'datetime',
        'read_at' => 'datetime',
        'failed_at' => 'datetime',
    ];

    public const STATUS_QUEUED = 'queued';
    public const STATUS_SENT = 'sent';
    public const STATUS_DELIVERED = 'delivered';
    public const STATUS_READ = 'read';
    public const STATUS_FAILED = 'failed';
    public const STATUS_SKIPPED = 'skipped';

    /**
     * Meta's two worlds, and they are not interchangeable.
     *
     * Utility covers messages about something the customer already did — a
     * booking confirmation, a reminder. Marketing is everything promotional,
     * priced differently, and refused outright to anyone who has not opted in.
     * Sending a marketing message under a utility template is how a WhatsApp
     * Business account gets restricted.
     */
    public const CATEGORY_UTILITY = 'utility';
    public const CATEGORY_MARKETING = 'marketing';

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function appointment()
    {
        return $this->belongsTo(Appointment::class, 'related_appointment_id');
    }

    public function campaign()
    {
        return $this->belongsTo(Campaign::class);
    }

    public function scopeMarketing($query)
    {
        return $query->where('category', self::CATEGORY_MARKETING);
    }

    /** Counts against an allowance only once it has actually left. */
    public function scopeBillable($query)
    {
        return $query->whereIn('status', [
            self::STATUS_SENT,
            self::STATUS_DELIVERED,
            self::STATUS_READ,
        ]);
    }
}
