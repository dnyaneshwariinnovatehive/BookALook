<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

/**
 * One rung of a reward ladder: a band of completed appointments and what each
 * one inside it is worth.
 *
 * `appointments_to` is null on the final rung, which runs forever.
 */
class WalletSchemeTier extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $fillable = [
        'scheme_id',
        'tier_order',
        'appointments_from',
        'appointments_to',
        'appointments_required',
        'coins_awarded',
    ];

    protected $casts = [
        'tier_order' => 'integer',
        'appointments_from' => 'integer',
        'appointments_to' => 'integer',
        'coins_awarded' => 'integer',
    ];

    public function scheme()
    {
        return $this->belongsTo(WalletScheme::class, 'scheme_id');
    }

    /** Does the salon's nth completed appointment fall on this rung? */
    public function covers(int $completedCount): bool
    {
        if ($completedCount < $this->appointments_from) {
            return false;
        }

        return $this->appointments_to === null || $completedCount <= $this->appointments_to;
    }
}
