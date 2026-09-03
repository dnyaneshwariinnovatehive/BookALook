<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class ProviderLeave extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $table = 'provider_leaves';

    protected $fillable = [
        'provider_id',
        'leave_date',
        'leave_type',
        'is_full_day',
        'start_time',
        'end_time',
        'reason',
        'status',
        'reviewed_by',
        'reviewed_at',
    ];

    protected $casts = [
        'is_full_day' => 'boolean',
        'leave_date' => 'date',
        'reviewed_at' => 'datetime',
    ];

    public function provider()
    {
        return $this->belongsTo(ServiceProvider::class, 'provider_id');
    }

    public function reviewer()
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }
}
