<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class AppointmentServiceAddition extends Model
{
    use HasUuids;

    protected $guarded = [];

    public function appointment()
    {
        return $this->belongsTo(Appointment::class);
    }

    public function service()
    {
        return $this->belongsTo(Service::class);
    }

    public function provider()
    {
        return $this->belongsTo(ServiceProvider::class, 'provider_id');
    }

    public function addedBy()
    {
        return $this->belongsTo(User::class, 'added_by');
    }
}
