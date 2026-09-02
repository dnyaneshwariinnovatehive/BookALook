<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class Banner extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $fillable = [
        'title',
        'image_url',
        'action_url',
        'target_scope',
        'target_city_id',
        'target_salon_id',
        'start_date',
        'end_date',
        'is_active',
    ];
    
    protected $casts = [
        'is_active' => 'boolean',
        'start_date' => 'date',
        'end_date' => 'date',
    ];
}
