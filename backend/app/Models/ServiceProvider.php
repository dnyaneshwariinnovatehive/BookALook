<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class ServiceProvider extends Model
{
    use HasUuids;
    
    protected $table = 'service_providers';

    protected $fillable = [
        'user_id',
        'salon_id',
        'specialization',
        'base_salary',
        'commission_percentage',
        'auto_approve_leave',
        'is_active',
        'joined_at',
    ];

    protected $casts = [
        'auto_approve_leave' => 'boolean',
        'is_active' => 'boolean',
        'base_salary' => 'decimal:2',
        'commission_percentage' => 'decimal:2',
        'joined_at' => 'date',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }

    public function services()
    {
        return $this->belongsToMany(Service::class, 'provider_services', 'provider_id', 'service_id')
                    ->withTimestamps();
    }
}
