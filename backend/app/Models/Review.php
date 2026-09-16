<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

/**
 * One customer's verdict on one visit.
 *
 * Tied to an appointment rather than to a salon, and the appointment id is
 * unique — a review has to be earned by actually having been served, and a
 * visit can only be rated once. That single constraint is what stops the
 * ratings on this platform from being worth nothing.
 */
class Review extends Model
{
    use HasUuids;

    protected $fillable = [
        'appointment_id',
        'customer_id',
        'salon_id',
        'rating',
        'comment',
    ];

    protected $casts = [
        'rating' => 'integer',
    ];

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }

    public function customer()
    {
        return $this->belongsTo(User::class, 'customer_id');
    }

    public function appointment()
    {
        return $this->belongsTo(Appointment::class);
    }
}
