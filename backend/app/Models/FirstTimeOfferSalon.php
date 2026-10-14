<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\Pivot;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class FirstTimeOfferSalon extends Pivot
{
    public $incrementing = false;

    protected $table = 'first_time_offer_salons';

    protected $fillable = [
        'offer_id',
        'salon_id',
    ];

    public function offer(): BelongsTo
    {
        return $this->belongsTo(FirstTimeOffer::class, 'offer_id');
    }

    public function salon(): BelongsTo
    {
        return $this->belongsTo(Salon::class, 'salon_id');
    }
}
