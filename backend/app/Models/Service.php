<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class Service extends Model
{
    use HasUuids, \Illuminate\Database\Eloquent\SoftDeletes;

    protected $fillable = [
        'salon_id',
        'template_id',
        'description',
        'price',
        'advance_percentage',
        'will_refund_advance_if_cancelled',
        'is_active',
        'display_order',
        'gender_focus',
    ];

    public function template()
    {
        return $this->belongsTo(ServiceTemplate::class, 'template_id');
    }

    public function salon()
    {
        return $this->belongsTo(Salon::class, 'salon_id');
    }

    public function combos()
    {
        return $this->belongsToMany(Combo::class, 'combo_services', 'service_id', 'combo_id')
                    ->withPivot('combo_special_price');
    }

    public function providers()
    {
        return $this->belongsToMany(ServiceProvider::class, 'provider_services', 'service_id', 'provider_id');
    }
}
