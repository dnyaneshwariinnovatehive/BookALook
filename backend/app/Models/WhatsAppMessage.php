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
    ];

    public const STATUS_QUEUED = 'queued';
    public const STATUS_SENT = 'sent';
    public const STATUS_FAILED = 'failed';
    public const STATUS_SKIPPED = 'skipped';

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function appointment()
    {
        return $this->belongsTo(Appointment::class, 'related_appointment_id');
    }
}
