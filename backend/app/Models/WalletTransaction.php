<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class WalletTransaction extends Model
{
    protected $fillable = [
        'salon_wallet_id',
        'type', // 'earned', 'redeemed'
        'amount',
        'description',
        'reference_type',
        'reference_id'
    ];
}
