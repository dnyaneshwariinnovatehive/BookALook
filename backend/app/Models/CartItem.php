<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class CartItem extends Model
{
    use HasUuids;

    protected $guarded = [];

    public function cart()
    {
        return $this->belongsTo(Cart::class);
    }

    public function service()
    {
        return $this->belongsTo(Service::class);
    }

    public function combo()
    {
        return $this->belongsTo(Combo::class);
    }

    public function preferredProvider()
    {
        return $this->belongsTo(ServiceProvider::class, 'preferred_provider_id');
    }
}
