<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\Pivot;

class ProviderService extends Pivot
{
    protected $table = 'provider_services';
    
    // foreign keys are provider_id and service_id

    protected $fillable = [
        'provider_id',
        'service_id',
    ];
}
