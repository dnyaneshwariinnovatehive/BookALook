<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class NotificationTemplate extends Model
{
    use HasUuids;

    protected $guarded = [];

    protected $casts = [
        'is_enabled' => 'boolean',
        'available_variables' => 'array',
        'channels' => 'array',
    ];

    /**
     * Get the active title. Falls back to default if null or empty.
     */
    public function getActiveTitleAttribute(): string
    {
        return !empty($this->title) ? $this->title : $this->default_title;
    }

    /**
     * Get the active message. Falls back to default if null or empty.
     */
    public function getActiveMessageAttribute(): string
    {
        return !empty($this->message) ? $this->message : $this->default_message;
    }
}
