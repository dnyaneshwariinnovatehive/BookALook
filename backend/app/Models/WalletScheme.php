<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class WalletScheme extends Model
{
    protected $fillable = [
        'name',
        'description',
        'coin_value',
        'is_active',
        'start_date',
        'end_date'
    ];

    public function tiers()
    {
        return $this->hasMany(WalletSchemeTier::class);
    }
}
