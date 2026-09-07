<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

/**
 * A reward ladder SuperAdmin publishes: "the first 250 completed online
 * appointments earn X, the next 100 earn more", and so on.
 *
 * Several schemes can exist over time; the one in force on a given date is the
 * active scheme whose window covers it. See WalletService::schemeInForceOn().
 */
class WalletScheme extends Model
{
    use HasUuids;

    /** Each appointment inside a band earns that band's coins. */
    public const MODE_PER_APPOINTMENT = 'per_appointment';

    /** A single lump is awarded when the band's last appointment lands. */
    public const MODE_ON_COMPLETION = 'on_completion';

    public const MODES = [self::MODE_PER_APPOINTMENT, self::MODE_ON_COMPLETION];

    protected $fillable = [
        'name',
        'description',
        'award_mode',
        'is_active',
        'starts_on',
        'ends_on',
        'created_by',
    ];

    protected $casts = [
        'is_active' => 'boolean',
        'starts_on' => 'date:Y-m-d',
        'ends_on' => 'date:Y-m-d',
    ];

    public function tiers()
    {
        return $this->hasMany(WalletSchemeTier::class, 'scheme_id')->orderBy('tier_order');
    }

    public function creator()
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }
}
