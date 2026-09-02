<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class Salon extends Model
{
    use HasUuids;

    protected $guarded = [];

    public function city()
    {
        return $this->belongsTo(City::class);
    }
}
