<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class ServiceCategory extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $fillable = [
        'name',
        'icon_url',
        'is_custom',
        'created_by_salon_id',
        'promoted_to_standard_at',
        'promoted_by',
        'is_active',
        'display_order',
    ];

    public function templates()
    {
        return $this->hasMany(ServiceTemplate::class, 'category_id');
    }
}
