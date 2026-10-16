<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AppUpdatePolicy extends Model
{
    use HasUuids;

    protected $table = 'app_update_policies';

    public const MODE_OPTIONAL = 'optional';
    public const MODE_MANDATORY = 'mandatory';
    public const MODES = [self::MODE_OPTIONAL, self::MODE_MANDATORY];

    protected $fillable = [
        'app',
        'latest_release_id',
        'minimum_release_id',
        'update_mode',
        'is_enforced',
        'enforce_at',
        'update_message',
        'android_store_url',
        'ios_store_url',
        'updated_by',
    ];

    protected $casts = [
        'is_enforced' => 'boolean',
        'enforce_at' => 'datetime',
    ];

    public function latestRelease(): BelongsTo
    {
        return $this->belongsTo(AppRelease::class, 'latest_release_id');
    }

    public function minimumRelease(): BelongsTo
    {
        return $this->belongsTo(AppRelease::class, 'minimum_release_id');
    }

    public function updater(): BelongsTo
    {
        return $this->belongsTo(User::class, 'updated_by');
    }

    /**
     * Determines whether enforcement is currently active.
     * Active when is_enforced is true AND (enforce_at is null or enforce_at <= now).
     */
    public function isEnforcementActive(): bool
    {
        if (! $this->is_enforced) {
            return false;
        }

        if ($this->enforce_at === null) {
            return true;
        }

        return now()->greaterThanOrEqualTo($this->enforce_at);
    }

    /**
     * Resolve store URLs with fallback to the latest release URLs.
     */
    public function resolveAndroidStoreUrl(): ?string
    {
        return $this->android_store_url ?: $this->latestRelease?->android_store_url;
    }

    public function resolveIosStoreUrl(): ?string
    {
        return $this->ios_store_url ?: $this->latestRelease?->ios_store_url;
    }
}
