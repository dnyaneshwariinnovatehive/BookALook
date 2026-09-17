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
        // The city as the owner typed it on the website form. Kept alongside
        // city_id because it is what they actually wrote, and a resolved id
        // cannot prove that.
        'city',
        'city_id',
        'sub_area_id',
        'message',
        'status',
        'assigned_collaborator_id',
        'assigned_at',
    ];

    protected $casts = [
        'assigned_at' => 'datetime',
    ];

    public function cityRecord()
    {
        return $this->belongsTo(City::class, 'city_id');
    }

    public function subArea()
    {
        return $this->belongsTo(SubArea::class, 'sub_area_id');
    }

    public function assignedCollaborator()
    {
        return $this->belongsTo(User::class, 'assigned_collaborator_id');
    }

    /**
     * The salon the assigned collaborator built from this enquiry, once they
     * have submitted it. Absent until then.
     */
    public function salon()
    {
        return $this->hasOne(Salon::class, 'enquiry_id');
    }
}
