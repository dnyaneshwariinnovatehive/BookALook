<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\Pivot;

class ComboService extends Pivot
{
    protected $table = 'combo_services';

    protected $fillable = [
        'combo_id',
        'service_id',
        'combo_special_price',
    ];

    protected $casts = [
        'combo_special_price' => 'decimal:2',
    ];
}
