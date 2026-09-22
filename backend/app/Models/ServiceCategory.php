<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class ServiceCategory extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $fillable = [
        'name',
        'icon_url',
        'is_custom',
        'created_by_salon_id',
        'promoted_to_standard_at',
        'promoted_by',
        'is_active',
        'display_order',
    ];

    public function templates()
    {
        return $this->hasMany(ServiceTemplate::class, 'category_id');
    }

    /**
     * The icon, on a host the caller can actually reach.
     *
     * Icons are stored as absolute URLs built at upload time, which bakes in
     * whatever host the dashboard happened to be on — usually
     * `http://localhost:8000`. That is fine in a browser on the same machine
     * and useless everywhere else: to an Android emulator `localhost` is the
     * emulator, and to a phone on the same wifi it is the phone. The image
     * silently fails and the app falls back to a generic shape, which looks
     * exactly like "the icon was never uploaded".
     *
     * So the stored path is kept and the host is rebuilt from the request the
     * client actually made. Anything hosted elsewhere — Cloudinary, a CDN — is
     * returned untouched, because that host is already correct for everyone.
     */
    public function publicIconUrl(): ?string
    {
        return self::reachableIcon($this->icon_url);
    }

    public static function reachableIcon(?string $stored): ?string
    {
        if (! $stored) {
            return null;
        }

        $marker = '/storage/';
        $at = strpos($stored, $marker);

        // Not one of ours: leave it alone.
        if ($at === false) {
            return $stored;
        }

        return url(substr($stored, $at));
    }
}
