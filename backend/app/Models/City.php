<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class City extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'name',
        'state',
        'is_active',
    ];

    protected $casts = [
        'is_active' => 'boolean',
    ];

    public function salons()
    {
        return $this->hasMany(Salon::class);
    }

    /**
     * Cities a customer can actually book in.
     *
     * The platform knows 500-odd Indian cities but trades in a handful. Offering
     * the rest in a picker sends customers to an empty screen and teaches them
     * the app has nothing in it — so the directory only ever offers cities with
     * a salon standing behind them.
     */
    public function scopeServiceable($query)
    {
        return $query->whereExists(
            fn ($sub) => $sub->selectRaw(1)
                ->from('salons')
                ->whereColumn('salons.city_id', 'cities.id')
                ->where('salons.status', 'active')
                ->whereNull('salons.deleted_at')
        );
    }

    /** How many salons are open here right now. */
    public function scopeWithOpenSalonCount($query)
    {
        return $query->withCount([
            'salons as salon_count' => fn ($q) => $q->where('status', 'active'),
        ]);
    }
}
