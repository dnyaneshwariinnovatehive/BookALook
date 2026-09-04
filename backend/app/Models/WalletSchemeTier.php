<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class WalletSchemeTier extends Model
{
    protected $fillable = [
        'wallet_scheme_id',
        'milestone_type',
        'milestone_value',
        'reward_coins'
    ];

    public function scheme()
    {
        return $this->belongsTo(WalletScheme::class, 'wallet_scheme_id');
    }
}
