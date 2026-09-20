<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * One send: a salon, a template, an audience and what became of it.
 *
 * The counters are denormalised on purpose. A campaign to two thousand people
 * is two thousand recipient rows, and the salon's campaign list would otherwise
 * aggregate all of them on every page load; the rows stay authoritative and
 * these are kept in step as receipts arrive.
 */
class Campaign extends Model
{
    use HasUuids;

    protected $fillable = [
        'salon_id',
        'campaign_template_id',
        'created_by',
        'name',
        'status',
        'audience',
        'variables',
        'scheduled_for',
        'recipients_count',
        'sent_count',
        'delivered_count',
        'read_count',
        'failed_count',
        'skipped_count',
        'cycle_start',
        'cycle_end',
        'started_at',
        'completed_at',
        'failure_reason',
    ];

    protected $casts = [
        'audience' => 'array',
        'variables' => 'array',
        'scheduled_for' => 'datetime',
        'started_at' => 'datetime',
        'completed_at' => 'datetime',
        'cycle_start' => 'date',
        'cycle_end' => 'date',
    ];

    public const STATUS_DRAFT = 'draft';
    public const STATUS_SCHEDULED = 'scheduled';
    public const STATUS_SENDING = 'sending';
    public const STATUS_SENT = 'sent';
    public const STATUS_FAILED = 'failed';
    public const STATUS_CANCELLED = 'cancelled';

    /**
     * States that have already consumed quota.
     *
     * A draft has not been sent and must not count; a cancelled one was stopped
     * before dispatch. Everything else has either gone out or is going out, and
     * the allowance was spent the moment it was committed to.
     */
    public const COUNTED_STATUSES = [
        self::STATUS_SCHEDULED,
        self::STATUS_SENDING,
        self::STATUS_SENT,
        self::STATUS_FAILED,
    ];

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }

    public function template()
    {
        return $this->belongsTo(CampaignTemplate::class, 'campaign_template_id');
    }

    public function recipients()
    {
        return $this->hasMany(CampaignRecipient::class);
    }

    public function creator()
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    /** Campaigns charged to the billing period covering $start. */
    public function scopeInCycle($query, $start, $end)
    {
        return $query->where('cycle_start', $start)->where('cycle_end', $end);
    }

    public function scopeCounted($query)
    {
        return $query->whereIn('status', self::COUNTED_STATUSES);
    }

    public function isEditable(): bool
    {
        return in_array($this->status, [self::STATUS_DRAFT, self::STATUS_SCHEDULED], true);
    }

    /**
     * Share of delivered messages that were opened.
     *
     * Against delivered rather than sent, because a message that never arrived
     * says nothing about whether the copy was any good.
     */
    public function readRate(): ?float
    {
        return $this->delivered_count > 0
            ? round($this->read_count / $this->delivered_count * 100, 1)
            : null;
    }

    public function deliveryRate(): ?float
    {
        return $this->sent_count > 0
            ? round($this->delivered_count / $this->sent_count * 100, 1)
            : null;
    }
}
