<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class SalonMedia extends Model
{
    use HasUuids;

    protected $guarded = [];

    protected $casts = [
        'is_cover' => 'boolean',
    ];

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }
}
