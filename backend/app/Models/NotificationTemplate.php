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
        'action_config' => 'array',
        'schedule_config' => 'array',
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

    /**
     * Get the active push title. Falls back to default if null or empty.
     */
    public function getActivePushTitleAttribute(): string
    {
        // If push title isn't specifically defined, fallback to default_push_title.
        // If default_push_title doesn't exist (e.g. for some types), fallback to active in-app title.
        $val = !empty($this->push_title) ? $this->push_title : $this->default_push_title;
        return !empty($val) ? $val : $this->active_title;
    }

    /**
     * Get the active push message. Falls back to default if null or empty.
     */
    public function getActivePushMessageAttribute(): string
    {
        $val = !empty($this->push_message) ? $this->push_message : $this->default_push_message;
        return !empty($val) ? $val : $this->active_message;
    }
}
