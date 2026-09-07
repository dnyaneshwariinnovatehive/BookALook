<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

/**
 * A day (or part of one) a staff member is away.
 *
 * `leave_type` decides whether it costs them anything: paid leave is time off
 * without a deduction, unpaid leave reduces that month's salary.
 */
class ProviderLeave extends Model
{
    use HasUuids;

    public $timestamps = false;

    public const TYPE_PAID = 'paid';
    public const TYPE_UNPAID = 'unpaid';

    public const STATUS_PENDING = 'pending';
    public const STATUS_APPROVED = 'approved';
    public const STATUS_REJECTED = 'rejected';

    protected $guarded = [];

    protected $casts = [
        'leave_date' => 'date:Y-m-d',
        'is_full_day' => 'boolean',
        'reviewed_at' => 'datetime',
    ];

    public function provider()
    {
        return $this->belongsTo(ServiceProvider::class, 'provider_id');
    }

    public function reviewer()
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }

    /** Half a day off costs half a day's pay. */
    public function dayFraction(): float
    {
        return $this->is_full_day ? 1.0 : 0.5;
    }
}
