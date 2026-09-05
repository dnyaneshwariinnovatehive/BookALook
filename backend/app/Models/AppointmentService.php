<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class AppointmentService extends Model
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

    public function servingProvider()
    {
        return $this->belongsTo(ServiceProvider::class, 'serving_provider_id');
    }
}
