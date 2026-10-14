<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\Pivot;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class FirstTimeOfferService extends Pivot
{
    public $incrementing = false;

    protected $table = 'first_time_offer_services';

    protected $fillable = [
        'offer_id',
        'service_template_id',
    ];

    public function offer(): BelongsTo
    {
        return $this->belongsTo(FirstTimeOffer::class, 'offer_id');
    }

    public function serviceTemplate(): BelongsTo
    {
        return $this->belongsTo(ServiceTemplate::class, 'service_template_id');
    }
}
