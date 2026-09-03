<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class ServiceTemplate extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $fillable = [
        'category_id',
        'name',
        'estimated_duration_minutes',
        'is_custom',
        'created_by_salon_id',
        'promoted_to_standard_at',
        'promoted_by',
        'is_active',
    ];

    public function category()
    {
        return $this->belongsTo(ServiceCategory::class, 'category_id');
    }
}
