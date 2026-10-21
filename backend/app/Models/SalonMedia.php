<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class SalonMedia extends Model
{
    use HasUuids;

    protected $guarded = [];

    protected $casts = [
        'is_cover' => 'boolean',
    ];

    protected $appends = [
        'file_path',
        'url',
    ];

    public function getFilePathAttribute()
    {
        return $this->file_url;
    }

    public function getUrlAttribute()
    {
        return $this->file_url;
    }

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }
}
