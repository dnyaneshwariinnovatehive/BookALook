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
}
