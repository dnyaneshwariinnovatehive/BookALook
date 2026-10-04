<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class Banner extends Model
{
    use HasUuids;

    protected $fillable = [
        'title',
        'banner_type',
        'config',
        'image_url',
        'action_url',
        'target_scope',
        'target_city_id',
        'target_salon_id',
        'target_sub_area_id',
        'start_date',
        'end_date',
        'is_active',
        'priority',
        'impressions',
        'clicks',
    ];

    protected $casts = [
        'is_active'   => 'boolean',
        'start_date'  => 'date',
        'end_date'    => 'date',
        'config'      => 'array',
        'priority'    => 'integer',
        'impressions' => 'integer',
        'clicks'      => 'integer',
    ];

    /* ── Relations ─────────────────────────────────────── */

    public function city()
    {
        return $this->belongsTo(City::class, 'target_city_id');
    }

    public function salon()
    {
        return $this->belongsTo(Salon::class, 'target_salon_id');
    }

    public function subArea()
    {
        return $this->belongsTo(SubArea::class, 'target_sub_area_id');
    }

    /* ── Helpers ────────────────────────────────────────── */

    public const TYPES = [
        'static',
        'combo_discount',
        'specific_combo',
        'new_arrivals',
        'category_spotlight',
        'seasonal',
    ];
}
