<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * A salon's screenshot of paying what a payout says it owes BookALook,
 * waiting for, or past, SuperAdmin's verification.
 */
class PayoutPaymentSubmission extends Model
{
    use HasUuids;

    public const STATUS_PENDING = 'pending';
    public const STATUS_APPROVED = 'approved';
    public const STATUS_REJECTED = 'rejected';

    protected $guarded = [];

    protected $casts = [
        'amount' => 'float',
        'reviewed_at' => 'datetime',
    ];

    public function payout()
    {
        return $this->belongsTo(SalonPayout::class, 'salon_payout_id');
    }

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }

    /** How the owner and SuperAdmin both see it. */
    public function present(): array
    {
        return [
            'id' => $this->id,
            'amount' => (float) $this->amount,
            'status' => $this->status,
            'screenshot_url' => $this->screenshot_url,
            'transaction_id' => $this->transaction_id,
            'note' => $this->note,
            'rejection_reason' => $this->rejection_reason,
            'submitted_at' => $this->created_at?->toIso8601String(),
            'reviewed_at' => $this->reviewed_at?->toIso8601String(),
        ];
    }
}
