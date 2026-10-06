<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class WhatsappAutomation extends Model
{
    use HasUuids;

    protected $fillable = [
        'key',
        'name',
        'description',
        'audience',
        'frequency_label',
        'is_enabled',
        'aisensy_campaign_name',
        'lead_time_minutes',
    ];

    protected $casts = [
        'is_enabled' => 'boolean',
        'lead_time_minutes' => 'integer',
    ];
}
