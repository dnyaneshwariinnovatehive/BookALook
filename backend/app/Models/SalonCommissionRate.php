<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Every commission rate a salon has ever been on.
 *
 * A settled payout has to be able to explain the rate it charged, and a salon
 * asking "why was I charged that?" has to be answerable months later. The rate
 * on the salon row is only the current one; this is the record behind it.
 */
class SalonCommissionRate extends Model
{
    use HasUuids;

    protected $guarded = [];

    protected $casts = [
        'percentage' => 'decimal:2',
        'effective_from' => 'date',
        'effective_to' => 'date',
    ];

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }

    public function setBy()
    {
        return $this->belongsTo(User::class, 'set_by');
    }

    /** The rate still in force has no closing date. */
    public function scopeCurrent($query)
    {
        return $query->whereNull('effective_to');
    }
}
