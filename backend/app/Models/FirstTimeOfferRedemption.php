<?php

namespace App\Models;

use Carbon\Carbon;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class FirstTimeOfferRedemption extends Model
{
    use HasFactory, HasUuids;

    public const STATUS_RESERVED = 'reserved';

    public const STATUS_COMMITTED = 'committed';

    public const STATUS_RELEASED = 'released';

    protected $fillable = [
        'offer_id',
        'customer_id',
        'customer_phone_hash',
        'salon_id',
        'appointment_id',
        'status',
        'active_entitlement_key',
        'scope',
        'discount_amount',
        'reserved_at',
        'committed_at',
        'released_at',
        'release_reason',
    ];

    protected $casts = [
        'discount_amount' => 'decimal:2',
        'reserved_at' => 'datetime',
        'committed_at' => 'datetime',
        'released_at' => 'datetime',
    ];

    /** Entitlement keys and phone hashes are internal security tokens — never leak to client JSON. */
    protected $hidden = [
        'active_entitlement_key',
        'customer_phone_hash',
    ];

    public function offer(): BelongsTo
    {
        return $this->belongsTo(FirstTimeOffer::class, 'offer_id');
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'customer_id');
    }

    public function salon(): BelongsTo
    {
        return $this->belongsTo(Salon::class, 'salon_id');
    }

    public function appointment(): BelongsTo
    {
        return $this->belongsTo(Appointment::class, 'appointment_id');
    }

    /**
     * Mark this reservation as committed after payment success.
     */
    public function commit(): bool
    {
        if ($this->status === self::STATUS_COMMITTED) {
            return true;
        }

        if ($this->status === self::STATUS_RELEASED) {
            // Cannot commit a released reservation directly without explicit recommit verification
            return false;
        }

        $this->status = self::STATUS_COMMITTED;
        $this->committed_at = Carbon::now();
        $saved = $this->save();

        if ($saved && $this->offer_id) {
            FirstTimeOffer::where('id', $this->offer_id)->increment('current_redemptions');
        }

        return $saved;
    }

    /**
     * Safely recommit an expired/released reservation when payment is cryptographically verified
     * and offer capacity and customer eligibility have been strictly re-validated under database locks.
     */
    public function recommit(string $entitlementKey): bool
    {
        if ($this->status === self::STATUS_COMMITTED) {
            return true;
        }

        $this->status = self::STATUS_COMMITTED;
        $this->active_entitlement_key = $entitlementKey;
        $this->committed_at = Carbon::now();
        $this->release_reason = null;
        $saved = $this->save();

        if ($saved && $this->offer_id) {
            FirstTimeOffer::where('id', $this->offer_id)->increment('current_redemptions');
        }

        return $saved;
    }

    /**
     * Release a temporary reservation (e.g. hold expired or abandoned).
     * Clears active_entitlement_key so uniqueness constraint is freed.
     */
    public function release(string $reason = 'abandoned'): bool
    {
        if ($this->status === self::STATUS_COMMITTED) {
            // Cannot release a committed redemption
            return false;
        }

        if ($this->status === self::STATUS_RELEASED) {
            return true;
        }

        $this->status = self::STATUS_RELEASED;
        $this->released_at = Carbon::now();
        $this->release_reason = $reason;
        // Clearing active_entitlement_key frees the database uniqueness constraint
        $this->active_entitlement_key = null;

        return $this->save();
    }
}
