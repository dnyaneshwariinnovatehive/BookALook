<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AppRelease extends Model
{
    use HasUuids;

    protected $table = 'app_releases';

    public const APP_CUSTOMER = 'customer';
    public const APP_PARTNER = 'partner';
    public const APPS = [self::APP_CUSTOMER, self::APP_PARTNER];

    public const STATUS_DRAFT = 'draft';
    public const STATUS_PUBLISHED = 'published';
    public const STATUS_RETIRED = 'retired';
    public const STATUSES = [self::STATUS_DRAFT, self::STATUS_PUBLISHED, self::STATUS_RETIRED];

    protected $fillable = [
        'app',
        'version',
        'build_number',
        'released_at',
        'release_notes',
        'android_store_url',
        'ios_store_url',
        'status',
        'created_by',
        'updated_by',
    ];

    protected $casts = [
        'build_number' => 'integer',
        'released_at' => 'datetime',
    ];

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function updater(): BelongsTo
    {
        return $this->belongsTo(User::class, 'updated_by');
    }

    public function scopeForApp(Builder $query, string $app): Builder
    {
        return $query->where('app', $app);
    }

    public function scopePublished(Builder $query): Builder
    {
        return $query->where('status', self::STATUS_PUBLISHED);
    }

    public function isPublished(): bool
    {
        return $this->status === self::STATUS_PUBLISHED;
    }

    public function isRetired(): bool
    {
        return $this->status === self::STATUS_RETIRED;
    }

    public function isDraft(): bool
    {
        return $this->status === self::STATUS_DRAFT;
    }
}
