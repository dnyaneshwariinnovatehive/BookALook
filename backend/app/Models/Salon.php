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

    public function subscriptions()
    {
        return $this->hasMany(SalonSubscription::class);
    }

    public function currentSubscription()
    {
        return $this->hasOne(SalonSubscription::class)->where('status', 'active')->latest('start_date');
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
