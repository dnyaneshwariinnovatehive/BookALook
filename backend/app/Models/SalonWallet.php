<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SalonWallet extends Model
{
    protected $primaryKey = 'salon_id';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;

    protected $fillable = [
        'salon_id',
        'coin_balance',
        'completed_online_appointments_count'
    ];

    public function transactions()
    {
        return $this->hasMany(WalletTransaction::class, 'salon_id', 'salon_id');
    }
}
