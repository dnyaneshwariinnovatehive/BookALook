<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class Combo extends Model
{
    use HasUuids;

    public const CATEGORY_SENTINEL = 'combo';

    public $timestamps = false;

    protected $fillable = [
        'salon_id',
        'name',
        'advance_percentage',
        'will_refund_advance_if_cancelled',
        'is_active',
    ];

    protected $casts = [
        'is_active' => 'boolean',
        'will_refund_advance_if_cancelled' => 'boolean',
        'advance_percentage' => 'decimal:2',
    ];

    protected $appends = [
        'price',
        'original_price',
    ];

    public function getPriceAttribute(): float
    {
        if ($this->relationLoaded('services')) {
            return (float) round($this->services->sum(function ($service) {
                return (float) ($service->pivot->combo_special_price ?? $service->price);
            }), 2);
        }

        return 0.0;
    }

    public function getOriginalPriceAttribute(): float
    {
        if ($this->relationLoaded('services')) {
            return (float) round($this->services->sum(function ($service) {
                return (float) $service->price;
            }), 2);
        }

        return 0.0;
    }

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }

    public function services()
    {
        return $this->belongsToMany(Service::class, 'combo_services', 'combo_id', 'service_id')
                    ->withPivot('combo_special_price');
    }
}
