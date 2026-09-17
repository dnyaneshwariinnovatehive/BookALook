<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

/**
 * A locality inside a city — Kothrud, Bandra West, Koramangala.
 *
 * The unit people actually think in. "Pune" covers a two-hour drive, so a city
 * on its own cannot answer "is this salon near me" or "is this collaborator
 * local to this enquiry". Owned by SuperAdmin so the list stays clean: two
 * spellings of the same locality would quietly split a neighbourhood in half.
 */
class SubArea extends Model
{
    use HasUuids;

    protected $fillable = ['city_id', 'name', 'is_active'];

    protected $casts = ['is_active' => 'boolean'];

    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }

    public function city()
    {
        return $this->belongsTo(City::class);
    }

    public function salons()
    {
        return $this->hasMany(Salon::class);
    }

    /** People who live or work here — customers and collaborators alike. */
    public function users()
    {
        return $this->hasMany(User::class);
    }
}
