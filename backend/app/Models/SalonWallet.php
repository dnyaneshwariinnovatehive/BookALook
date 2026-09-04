<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SalonWallet extends Model
{
    protected $fillable = [
        'salon_id',
        'balance'
    ];

    public function transactions()
    {
        return $this->hasMany(WalletTransaction::class);
    }
}
