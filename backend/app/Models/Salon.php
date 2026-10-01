<?php

namespace App\Models;

use App\Support\BillingModel;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class Salon extends Model
{
    use HasUuids;

    protected $guarded = [];

    protected $casts = [
        'commission_opt_in' => 'boolean',
        'commission_percentage' => 'decimal:2',
        'commission_rate_effective_from' => 'date',
    ];

    public function city()
    {
        return $this->belongsTo(City::class);
    }

    /** The locality the salon sits in — finer than the city, which in Pune
     *  covers a two-hour drive. */
    public function subArea()
    {
        return $this->belongsTo(SubArea::class);
    }

    public function admin()
    {
        return $this->belongsTo(User::class, 'admin_id');
    }

    /**
     * The collaborator who owns this salon's onboarding.
     *
     * Salons that arrived through an enquiry inherit theirs from that enquiry.
     * Salons that registered themselves from the partner app arrive with none,
     * so SuperAdmin assigns one here in the directory.
     */
    public function assignedCollaborator()
    {
        return $this->belongsTo(User::class, 'assigned_collaborator_id');
    }

    /**
     * The enquiry this salon was onboarded from, when it came in that way.
     * Null for salons that registered themselves from the partner app.
     */
    public function enquiry()
    {
        return $this->belongsTo(SalonEnquiry::class, 'enquiry_id');
    }

    public function media()
    {
        return $this->hasMany(SalonMedia::class)->orderBy('sort_order');
    }

    public function reviews()
    {
        return $this->hasMany(Review::class);
    }

    public function complaints()
    {
        return $this->hasMany(Complaint::class);
    }

    public function workingHours()
    {
        return $this->hasMany(SalonWorkingHour::class)->orderBy('day_of_week');
    }

    public function services()
    {
        return $this->hasMany(Service::class);
    }

    public function providers()
    {
        return $this->hasMany(ServiceProvider::class);
    }

    public function combos()
    {
        return $this->hasMany(Combo::class);
    }

    /**
     * Salons that can actually be booked for a given catalogue category.
     *
     * The offer is a *service* the salon has switched on, not a category that
     * happens to exist somewhere in its templates — a switched-off service is
     * not something a customer can book, so listing the salon is a dead end.
     *
     * Also accepts the combo sentinel, which is not a catalogue category at all
     * but means "offers a package", so it is answered from the combos instead.
     */
    public function scopeProvidingCategory($query, string $categoryId)
    {
        if (strtolower($categoryId) === Combo::CATEGORY_SENTINEL) {
            return $query->whereHas('combos', function ($combos) {
                $combos->where('is_active', true);
            });
        }

        return $query->whereHas('services', function ($services) use ($categoryId) {
            $services->where('is_active', true)
                ->whereHas('template', function ($template) use ($categoryId) {
                    $template->where('category_id', $categoryId);
                });
        });
    }

    public function subscriptions()
    {
        return $this->hasMany(SalonSubscription::class);
    }

    public function currentSubscription()
    {
        return $this->hasOne(SalonSubscription::class)->where('status', 'active')->latest('start_date');
    }

    /**
     * The most recent subscription of any status.
     *
     * [self::currentSubscription] alone cannot tell "never had a plan" apart
     * from "had one and let it lapse" — both answer null. Those are opposite
     * things to say to a collaborator about a salon they set up, so anything
     * reporting on subscription health needs both relations.
     */
    public function latestSubscription()
    {
        return $this->hasOne(SalonSubscription::class)->latestOfMany('start_date');
    }

    public function commissionRates()
    {
        return $this->hasMany(SalonCommissionRate::class)->orderByDesc('effective_from');
    }

    public function payouts()
    {
        return $this->hasMany(SalonPayout::class);
    }

    /**
     * Which arrangement the salon trades under.
     *
     * The salon's own flag is the answer, not the subscription row — a renewal
     * replaces that row and used to lose the arrangement with it.
     */
    public function billingModel(): string
    {
        return $this->commission_opt_in ? BillingModel::COMMISSION : BillingModel::SUBSCRIPTION;
    }

    public function isOnCommissionModel(): bool
    {
        return (bool) $this->commission_opt_in;
    }
}
