<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class Salon extends Model
{
    use HasUuids;

    protected $guarded = [];

    public function city()
    {
        return $this->belongsTo(City::class);
    }

    public function admin()
    {
        return $this->belongsTo(User::class, 'admin_id');
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
}
