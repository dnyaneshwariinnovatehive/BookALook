<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class ProviderWorkingHour extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $fillable = [
        'provider_id',
        'day_of_week',
        'is_weekly_off',
        'shift_start',
        'shift_end',
        'break_start',
        'break_end',
    ];

    protected $casts = [
        'is_weekly_off' => 'boolean',
    ];
}
