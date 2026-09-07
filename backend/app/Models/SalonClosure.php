<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

/**
 * A day the salon is shut. Creating one both blocks new bookings for that date
 * and, when triggers_mass_reschedule is set, releases every appointment already
 * on it for a free reschedule.
 */
class SalonClosure extends Model
{
    use HasUuids;

    protected $guarded = [];

    protected $casts = [
        'closed_date' => 'date:Y-m-d',
        'triggers_mass_reschedule' => 'boolean',
        'reschedule_processed' => 'boolean',
        'processed_at' => 'datetime',
        'reopened_at' => 'datetime',
    ];

    /** Closures still in force. A reopened day takes bookings again. */
    public function scopeActive($query)
    {
        return $query->whereNull('reopened_at');
    }

    public function isActive(): bool
    {
        return $this->reopened_at === null;
    }

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }

    public function appointments()
    {
        return $this->hasMany(Appointment::class, 'salon_closure_id');
    }

    public function creator()
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function processor()
    {
        return $this->belongsTo(User::class, 'processed_by');
    }
}
