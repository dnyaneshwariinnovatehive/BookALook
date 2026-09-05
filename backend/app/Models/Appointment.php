<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class Appointment extends Model
{
    use HasUuids;

    protected $guarded = [];

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
}
