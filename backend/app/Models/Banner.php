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
        'media_kind',
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

    /**
     * Media axis — deliberately separate from TYPES.
     * 'image'    → static raster only (jpg/jpeg/png)
     * 'animated' → animated raster only (gif/webp)
     */
    public const MEDIA_KINDS = ['image', 'animated'];

    public const STATIC_EXTENSIONS = ['jpg', 'jpeg', 'png'];

    public const ANIMATED_EXTENSIONS = ['gif', 'webp'];

    /** Every extension allowed on an image_url (static ∪ animated). */
    public const IMAGE_EXTENSIONS = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
}
