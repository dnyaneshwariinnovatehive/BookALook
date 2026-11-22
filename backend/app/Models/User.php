<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\SoftDeletes;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    /** @use HasFactory<\Database\Factories\UserFactory> */
    use HasApiTokens, HasFactory, Notifiable, HasUuids, SoftDeletes;

    /**
     * The attributes that are mass assignable.
     *
     * @var list<string>
     */
    protected $fillable = [
        'role',
        'name',
        'phone',
        'email',
        'password_hash',
        'gender',
        'date_of_birth',
        'address',
        'pincode',
        'city_id',
        'sub_area_id',
        'is_active',
        'last_login_at',
    ];

    /**
     * The attributes that should be hidden for serialization.
     *
     * @var list<string>
     */
    protected $hidden = [
        'password_hash',
        'remember_token',
    ];

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'password_hash' => 'hashed',
            'is_active' => 'boolean',
            'last_login_at' => 'datetime',
            'date_of_birth' => 'date',
        ];
    }

    /**
     * Which app an account belongs to. A phone number (or email) is unique per
     * account type, not across everyone: the same person can have a customer
     * account and one partner account. Owner, staff and collaborator are all
     * 'partner', so a number is still only one of those three.
     */
    public const ACCOUNT_CUSTOMER = 'customer';
    public const ACCOUNT_PARTNER = 'partner';

    /** Roles that sign in to the Partner app. */
    public const PARTNER_ROLES = ['admin', 'service_provider', 'collaborator'];

    public static function accountTypeFor(?string $role): string
    {
        return $role === 'customer' ? self::ACCOUNT_CUSTOMER : self::ACCOUNT_PARTNER;
    }

    /**
     * account_type always follows role, so no caller can create a customer
     * row on the partner side or the reverse.
     */
    protected static function booted(): void
    {
        static::saving(function (User $user) {
            $user->account_type = self::accountTypeFor($user->role);
        });
    }

    /**
     * Validation rule: [column] (phone or email) not already used by another
     * account of [accountType]. Use this instead of `unique:users`, which
     * would wrongly block a number that only has an account on the other side.
     */
    public static function uniqueOn(string $accountType, string $column, ?string $ignoreId = null): \Illuminate\Validation\Rules\Unique
    {
        return \Illuminate\Validation\Rule::unique('users', $column)
            ->where('account_type', $accountType)
            ->ignore($ignoreId);
    }

    /** The message for a partner-side phone clash. */
    public const PARTNER_PHONE_TAKEN = 'This number already has a partner account (salon owner, staff or collaborator).';

    /** Customer-app accounts. */
    public function scopeCustomerAccounts($query)
    {
        return $query->where('account_type', self::ACCOUNT_CUSTOMER);
    }

    /** Partner-app (and platform) accounts. */
    public function scopePartnerAccounts($query)
    {
        return $query->where('account_type', self::ACCOUNT_PARTNER);
    }

    /**
     * Get the password for the user.
     *
     * @return string
     */
    public function getAuthPasswordName()
    {
        return 'password_hash';
    }

    /**
     * Get the customer's favourite salons.
     */
    public function favouriteSalons()
    {
        return $this->belongsToMany(Salon::class, 'favourite_salons', 'customer_id', 'salon_id')->withTimestamps();
    }

    /** The market this customer browses in. Null until they have chosen one. */
    public function city()
    {
        return $this->belongsTo(City::class);
    }

    /**
     * The locality this person belongs to.
     *
     * For a customer it narrows what they are shown; for a collaborator it is
     * what an incoming enquiry is matched against, so the person sent to a
     * salon is one who already works nearby.
     */
    public function subArea()
    {
        return $this->belongsTo(SubArea::class);
    }

    public function firstTimeOfferRedemptions()
    {
        return $this->hasMany(FirstTimeOfferRedemption::class, 'customer_id');
    }
}
