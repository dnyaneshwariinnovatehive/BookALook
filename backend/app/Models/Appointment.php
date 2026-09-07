<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class Appointment extends Model
{
    use HasUuids;

    protected $guarded = [];

    /** The QR hash is a credential — never ship it to a client. */
    protected $hidden = ['qr_token_hash'];

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }

    public function customer()
    {
        return $this->belongsTo(User::class, 'customer_id');
    }

    public function appointedProvider()
    {
        return $this->belongsTo(ServiceProvider::class, 'appointed_provider_id');
    }

    public function servingProvider()
    {
        return $this->belongsTo(ServiceProvider::class, 'serving_provider_id');
    }

    public function services()
    {
        return $this->hasMany(AppointmentService::class);
    }

    public function serviceAdditions()
    {
        return $this->hasMany(AppointmentServiceAddition::class);
    }

    public function cancelledByUser()
    {
        return $this->belongsTo(User::class, 'cancelled_by_user_id');
    }

    /** Set when an emergency closure released this booking. */
    public function salonClosure()
    {
        return $this->belongsTo(SalonClosure::class, 'salon_closure_id');
    }
}
