<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * A message from a salon owner to BookALook, and SuperAdmin's answer.
 */
class SalonSupportRequest extends Model
{
    use HasUuids;

    public const STATUS_OPEN = 'open';
    public const STATUS_RESOLVED = 'resolved';

    /** What the owner can write about, and how each reads to a person. */
    public const TOPICS = [
        'settlement_query' => 'Settlement query',
        'payout_request' => 'Request my payout',
        'renewal_help' => 'Help with renewal',
        'other' => 'Something else',
    ];

    protected $guarded = [];

    protected $casts = [
        'replied_at' => 'datetime',
        'resolved_at' => 'datetime',
    ];

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function payout()
    {
        return $this->belongsTo(SalonPayout::class, 'salon_payout_id');
    }

    public function present(): array
    {
        return [
            'id' => $this->id,
            'salon_id' => $this->salon_id,
            'topic' => $this->topic,
            'topic_label' => self::TOPICS[$this->topic] ?? 'Something else',
            'message' => $this->message,
            'status' => $this->status,
            'reply' => $this->reply,
            'replied_at' => $this->replied_at?->toIso8601String(),
            'resolved_at' => $this->resolved_at?->toIso8601String(),
            'created_at' => $this->created_at?->toIso8601String(),
            'payout' => $this->payout ? [
                'id' => $this->payout->id,
                'cycle_start_date' => $this->payout->cycle_start_date,
                'cycle_end_date' => $this->payout->cycle_end_date,
                'net_amount' => (float) $this->payout->net_amount,
                'status' => $this->payout->status,
            ] : null,
        ];
    }
}
