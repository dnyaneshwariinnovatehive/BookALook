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
        return $this->belongsTo(ServiceTemplate::class, 'template_id')->withTrashed();
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

    /**
     * Retrieve all active services in the given salon that have no active
     * provider assigned (including regular staff and Admin provider).
     */
    public static function getUnassignedForSalon(string $salonId)
    {
        return static::with(['template.category'])
            ->where('salon_id', $salonId)
            ->where('is_active', true)
            ->whereDoesntHave('providers', function ($q) use ($salonId) {
                $q->where('service_providers.salon_id', $salonId)
                  ->where('service_providers.is_active', true)
                  ->whereNull('service_providers.deleted_at');
            })
            ->orderBy('display_order')
            ->orderBy('created_at')
            ->get();
    }

    /**
     * Format a collection of unassigned services into a clean, consistent array.
     */
    public static function formatUnassigned(iterable $services)
    {
        return collect($services)->map(function ($s) {
            return [
                'id' => $s->id,
                'name' => $s->template->name ?? $s->description ?? 'Service',
                'category_name' => $s->template->category->name ?? 'General',
                'price' => (float) $s->price,
                'gender_focus' => $s->gender_focus,
                'duration_minutes' => $s->template->estimated_duration_minutes ?? null,
            ];
        })->values();
    }
}
