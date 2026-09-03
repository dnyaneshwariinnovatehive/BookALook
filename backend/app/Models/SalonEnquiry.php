<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class SalonEnquiry extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'salon_name',
        'owner_name',
        'phone',
        'city',
        'message',
        'status',
        'assigned_collaborator_id',
        'assigned_at',
    ];

    protected $casts = [
        'assigned_at' => 'datetime',
    ];

    public function assignedCollaborator()
    {
        return $this->belongsTo(User::class, 'assigned_collaborator_id');
    }
}
