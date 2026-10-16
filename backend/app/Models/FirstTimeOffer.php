<?php

namespace App\Models;

use Carbon\Carbon;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class FirstTimeOffer extends Model
{
    use HasFactory, HasUuids, SoftDeletes;

    public const SCOPE_NEW_TO_PLATFORM = 'new_to_platform';

    public const SCOPE_NEW_TO_SALON = 'new_to_salon';

    public const TYPE_PERCENTAGE = 'percentage';

    public const TYPE_FLAT = 'flat';

    protected $fillable = [
        'salon_id',
        'name',
        'description',
        'scope',
        'discount_type',
        'discount_value',
        'max_discount_cap',
        'min_service_price',
        'min_eligible_subtotal',
        'min_total_booking_subtotal',
        'is_active',
        'starts_at',
        'ends_at',
        'max_redemptions',
        'current_redemptions',
    ];

    protected $casts = [
        'is_active' => 'boolean',
        'discount_value' => 'decimal:2',
        'max_discount_cap' => 'decimal:2',
        'min_service_price' => 'decimal:2',
        'min_eligible_subtotal' => 'decimal:2',
        'min_total_booking_subtotal' => 'decimal:2',
        'starts_at' => 'datetime',
        'ends_at' => 'datetime',
        'max_redemptions' => 'integer',
        'current_redemptions' => 'integer',
    ];

    /**
     * Service templates targeted explicitly by this offer.
     */
    public function serviceTemplates(): BelongsToMany
    {
        return $this->belongsToMany(
            ServiceTemplate::class,
            'first_time_offer_services',
            'offer_id',
            'service_template_id'
        )->using(FirstTimeOfferService::class)->withTimestamps();
    }

    /**
     * Direct relationship to pivot records.
     */
    public function offerServices(): HasMany
    {
        return $this->hasMany(FirstTimeOfferService::class, 'offer_id');
    }

    /**
     * Direct salon owner (if null, platform-wide offer owned by SuperAdmin).
     */
    public function salon()
    {
        return $this->belongsTo(Salon::class, 'salon_id');
    }

    /**
     * Participating salons (if empty for new_to_platform, all salons participate).
     */
    public function participatingSalons(): BelongsToMany
    {
        return $this->belongsToMany(
            Salon::class,
            'first_time_offer_salons',
            'offer_id',
            'salon_id'
        )->using(FirstTimeOfferSalon::class)->withTimestamps();
    }

    /**
     * Direct relationship to salon pivot records.
     */
    public function offerSalons(): HasMany
    {
        return $this->hasMany(FirstTimeOfferSalon::class, 'offer_id');
    }

    /**
     * Customer redemptions/reservations for this offer.
     */
    public function redemptions(): HasMany
    {
        return $this->hasMany(FirstTimeOfferRedemption::class, 'offer_id');
    }

    /**
     * Scope query to offers that are active and currently within their validity window.
     */
    public function scopeActive($query)
    {
        $now = Carbon::now();

        return $query->where('is_active', true)
            ->where(function ($q) use ($now) {
                $q->whereNull('starts_at')->orWhere('starts_at', '<=', $now);
            })
            ->where(function ($q) use ($now) {
                $q->whereNull('ends_at')->orWhere('ends_at', '>=', $now);
            });
    }

    /**
     * Whether this offer is currently active and within its schedule.
     */
    public function isCurrentlyValid(): bool
    {
        if (! $this->is_active) {
            return false;
        }

        $now = Carbon::now();

        if ($this->starts_at && $now->lt($this->starts_at)) {
            return false;
        }

        if ($this->ends_at && $now->gt($this->ends_at)) {
            return false;
        }

        return ! $this->isRedemptionLimitReached();
    }

    /**
     * Whether the campaign-wide redemption limit has been met.
     */
    public function isRedemptionLimitReached(): bool
    {
        if ($this->max_redemptions === null) {
            return false;
        }

        return $this->current_redemptions >= $this->max_redemptions;
    }

    /**
     * Check if a specific salon participates in this offer.
     */
    public function participates(string $salonId): bool
    {
        if ($this->salon_id !== null) {
            return $this->salon_id === $salonId;
        }

        if ($this->scope === self::SCOPE_NEW_TO_SALON) {
            return $this->participatingSalons()->where('salons.id', $salonId)->exists();
        }

        // For new_to_platform: if salons are specified, restrict to them; if none specified, all participate.
        $hasRestrictedSalons = $this->participatingSalons()->exists();
        if (! $hasRestrictedSalons) {
            return true;
        }

        return $this->participatingSalons()->where('salons.id', $salonId)->exists();
    }

    /**
     * Check if a specific service template is targeted.
     */
    public function targetsTemplate(string $serviceTemplateId): bool
    {
        return $this->serviceTemplates()->where('service_templates.id', $serviceTemplateId)->exists();
    }

    /**
     * Compute a deterministic server-side HMAC-SHA256 hash for a normalized phone number.
     * Prevents raw phone numbers from leaking into entitlement keys or logs, while
     * maintaining stable customer identity across account re-registration.
     */
    public static function hashPhone(?string $phone): ?string
    {
        if (! $phone || str_starts_with($phone, 'del_')) {
            return null;
        }

        // Strip non-digits
        $clean = preg_replace('/\D+/', '', $phone);
        // Normalize 12-digit Indian phone starting with 91 to 10-digit
        if (strlen($clean) === 12 && str_starts_with($clean, '91')) {
            $clean = substr($clean, 2);
        }

        if (empty($clean)) {
            return null;
        }

        $salt = config('app.key') ?: 'bookalook_entitlement_salt';

        return hash_hmac('sha256', $clean, $salt);
    }

    /**
     * Generate the deterministic entitlement key for concurrency locking.
     */
    public static function generateEntitlementKey(
        string $scope,
        string $offerId,
        string $customerId,
        ?string $salonId = null,
        ?string $phoneHash = null
    ): string {
        $ident = $phoneHash ? "ph:{$phoneHash}" : "cust:{$customerId}";

        if ($scope === self::SCOPE_NEW_TO_SALON && $salonId) {
            return "fto:{$offerId}:salon:{$salonId}:{$ident}";
        }

        return "fto:{$offerId}:{$ident}";
    }

    /**
     * Helper to get this offer's entitlement key for a customer & salon.
     */
    public function makeEntitlementKey(User|string $customer, ?string $salonId = null): string
    {
        $customerId = $customer instanceof User ? $customer->id : $customer;
        $phoneHash = null;

        if ($customer instanceof User && ! empty($customer->phone)) {
            $phoneHash = static::hashPhone($customer->phone);
        }

        return static::generateEntitlementKey($this->scope, $this->id, $customerId, $salonId, $phoneHash);
    }

    /**
     * Build validation rules for creating/updating an offer, enforcing platform policy limits.
     *
     * @param  array<string, mixed>  $input
     * @return array<string, array<int, mixed>>
     */
    public static function validationRules(array $input = [], bool $isSalonScoped = false): array
    {
        $discountType = $input['discount_type'] ?? self::TYPE_PERCENTAGE;

        $minPercentage = (float) PlatformPolicySetting::value('first_time_discount_min_percentage', 5);
        $maxPercentage = (float) PlatformPolicySetting::value('first_time_discount_max_percentage', 50);

        $minFlat = (float) PlatformPolicySetting::value('first_time_discount_min_flat_amount', 1.0);
        $maxFlat = (float) PlatformPolicySetting::value('first_time_discount_max_flat_amount', 1000.0);

        $platformMaxCap = (float) PlatformPolicySetting::value('first_time_discount_platform_max_cap', 5000.0);

        $valueRules = match ($discountType) {
            self::TYPE_FLAT => ['required', 'numeric', "min:{$minFlat}", "max:{$maxFlat}"],
            default => ['required', 'numeric', "min:{$minPercentage}", "max:{$maxPercentage}"],
        };

        $scope = $input['scope'] ?? null;
        $salonRules = $isSalonScoped
            ? ['nullable', 'array']
            : ($scope === self::SCOPE_NEW_TO_SALON
                ? ['required', 'array', 'min:1']
                : ['nullable', 'array']);

        return [
            'name' => ['required', 'string', 'max:150'],
            'description' => ['nullable', 'string'],
            'scope' => ['required', 'in:'.self::SCOPE_NEW_TO_PLATFORM.','.self::SCOPE_NEW_TO_SALON],
            'discount_type' => ['required', 'in:'.self::TYPE_PERCENTAGE.','.self::TYPE_FLAT],
            'discount_value' => $valueRules,
            'max_discount_cap' => ['nullable', 'numeric', 'min:0', "max:{$platformMaxCap}"],
            'min_service_price' => ['nullable', 'numeric', 'min:0'],
            'min_eligible_subtotal' => ['nullable', 'numeric', 'min:0'],
            'min_total_booking_subtotal' => ['nullable', 'numeric', 'min:0'],
            'is_active' => ['boolean'],
            'starts_at' => ['nullable', 'date'],
            'ends_at' => ['nullable', 'date', 'after_or_equal:starts_at'],
            'max_redemptions' => ['nullable', 'integer', 'min:1'],
            'service_template_ids' => ['required', 'array', 'min:1'],
            'service_template_ids.*' => ['uuid', 'exists:service_templates,id'],
            'salon_ids' => $salonRules,
            'salon_ids.*' => ['uuid', 'exists:salons,id'],
        ];
    }
}
