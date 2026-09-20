<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * One person on one campaign.
 *
 * Skipped rows are kept rather than filtered out before writing. "Went to 180
 * of your 240 customers, and here is why the other 60 did not hear from you"
 * is a far more useful answer than a smaller number with no explanation — and
 * the commonest reason, an opt-out, is one the salon needs to see.
 */
class CampaignRecipient extends Model
{
    use HasUuids;

    protected $fillable = [
        'campaign_id',
        'user_id',
        'phone',
        'name',
        'variables',
        'whatsapp_message_id',
        'status',
        'skip_reason',
    ];

    protected $casts = [
        'variables' => 'array',
    ];

    public const STATUS_PENDING = 'pending';
    public const STATUS_QUEUED = 'queued';
    public const STATUS_SENT = 'sent';
    public const STATUS_DELIVERED = 'delivered';
    public const STATUS_READ = 'read';
    public const STATUS_FAILED = 'failed';
    public const STATUS_SKIPPED = 'skipped';

    public const SKIP_OPTED_OUT = 'opted_out';
    public const SKIP_NO_CONSENT = 'no_consent';
    public const SKIP_INVALID_PHONE = 'invalid_phone';
    public const SKIP_OVER_QUOTA = 'over_quota';
    public const SKIP_DAILY_CAP = 'daily_cap';

    /** How each skip reads to the salon. */
    public const SKIP_LABELS = [
        self::SKIP_OPTED_OUT => 'Asked not to be messaged',
        self::SKIP_NO_CONSENT => 'Has not opted in to marketing',
        self::SKIP_INVALID_PHONE => 'Phone number is not usable',
        self::SKIP_OVER_QUOTA => 'Beyond this month\'s message allowance',
        self::SKIP_DAILY_CAP => 'Beyond today\'s sending cap',
    ];

    public function campaign()
    {
        return $this->belongsTo(Campaign::class);
    }

    public function message()
    {
        return $this->belongsTo(WhatsAppMessage::class, 'whatsapp_message_id');
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function skipLabel(): ?string
    {
        return $this->skip_reason ? (self::SKIP_LABELS[$this->skip_reason] ?? $this->skip_reason) : null;
    }
}
