<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

/**
 * One staff member's pay for one month.
 *
 * Everything that went into the figure is snapshotted here — the salary and
 * commission rate in force, the working-day divisor, the leave taken — so a
 * payslip issued in March still explains itself in December after the rates
 * have moved on.
 */
class SalaryPayout extends Model
{
    use HasUuids;

    public const STATUS_PENDING = 'pending';
    public const STATUS_PAID = 'paid';

    protected $guarded = [];

    protected $casts = [
        'salary_month' => 'date:Y-m-d',
        'base_salary_snapshot' => 'decimal:2',
        'commission_percentage_snapshot' => 'decimal:2',
        'commission_earned' => 'decimal:2',
        'unpaid_leave_days' => 'decimal:1',
        'paid_leave_days' => 'decimal:1',
        'unpaid_leave_deduction' => 'decimal:2',
        'other_adjustments' => 'decimal:2',
        'daily_rate' => 'decimal:2',
        'total_payable' => 'decimal:2',
        'working_days_in_month' => 'integer',
        'approved_at' => 'datetime',
        'paid_at' => 'datetime',
        'calculated_at' => 'datetime',
    ];

    public function provider()
    {
        return $this->belongsTo(ServiceProvider::class, 'provider_id');
    }

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }

    public function paidBy()
    {
        return $this->belongsTo(User::class, 'paid_by');
    }

    public function isPaid(): bool
    {
        return $this->status === self::STATUS_PAID;
    }
}
