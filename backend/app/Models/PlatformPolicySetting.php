<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PlatformPolicySetting extends Model
{
    public $timestamps = false;
    protected $primaryKey = 'setting_key';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'setting_key',
        'setting_value',
        'data_type',
        'description',
        'updated_by',
    ];
}
