<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class Appointment extends Model
{
    use HasUuids;

    protected $guarded = [];

    protected $casts = [
        'first_time_discount_amount' => 'decimal:2',
    ];

    /** The QR hash and internal phone hash are credentials/internal identifiers — never ship them to a client. */
    protected $hidden = ['qr_token_hash', 'customer_phone_hash'];

    /** Changes that move what the salon's screens show. */
    private const SYNCED_FIELDS = [
        'status', 'appointment_date', 'start_time', 'end_time',
        'appointed_provider_id', 'serving_provider_id', 'total_amount',
    ];

    /**
     * Live sync: when a booking appears or changes, the salon's open partner
     * apps are nudged to refresh. Sent after the transaction commits, so a
     * phone never reloads before the change is there to see, and held back a
     * couple of seconds so the several saves one booking makes become one push.
     */
    protected static function booted(): void
    {
        static::created(fn (Appointment $appointment) => $appointment->nudgeSalon());

        static::updated(function (Appointment $appointment) {
            if ($appointment->wasChanged(self::SYNCED_FIELDS)) {
                $appointment->nudgeSalon();
            }
        });
    }

    private function nudgeSalon(): void
    {
        if (! $this->salon_id) {
            return;
        }

        if (! \Illuminate\Support\Facades\Cache::add('salon_sync:' . $this->salon_id, true, 3)) {
            return;
        }

        \App\Jobs\SendSalonSyncJob::dispatch($this->salon_id, $this->id)
            ->delay(now()->addSeconds(2))
            ->afterCommit();
    }

    public function firstTimeOffer()
    {
        return $this->belongsTo(FirstTimeOffer::class, 'first_time_offer_id');
    }

    public function firstTimeOfferRedemption()
    {
        return $this->hasOne(FirstTimeOfferRedemption::class, 'appointment_id');
    }

    public function salon()
    {
        return $this->belongsTo(Salon::class);
    }

    public function customer()
    {
        return $this->belongsTo(User::class, 'customer_id');
    }

    public function appointedProvider()
    {
        return $this->belongsTo(ServiceProvider::class, 'appointed_provider_id');
    }

    public function servingProvider()
    {
        return $this->belongsTo(ServiceProvider::class, 'serving_provider_id');
    }

    public function services()
    {
        return $this->hasMany(AppointmentService::class);
    }

    public function serviceAdditions()
    {
        return $this->hasMany(AppointmentServiceAddition::class);
    }

    /**
     * The invoice for this booking, when one has been raised.
     *
     * At most one — the invoices table holds a unique key on appointment_id —
     * and not always present: an invoice is raised on demand, and a booking
     * whose basket has nothing to charge has no document to show.
     */
    public function invoice()
    {
        return $this->hasOne(Invoice::class);
    }

    public function cancelledByUser()
    {
        return $this->belongsTo(User::class, 'cancelled_by_user_id');
    }

    /** Set when an emergency closure released this booking. */
    /**
     * The customer's verdict on this visit, once they have given one. At most
     * one — the reviews table holds a unique key on appointment_id, so a visit
     * cannot be rated twice.
     */
    public function review()
    {
        return $this->hasOne(Review::class);
    }

    public function salonClosure()
    {
        return $this->belongsTo(SalonClosure::class, 'salon_closure_id');
    }

    public function paymentCollector()
    {
        return $this->belongsTo(User::class, 'payment_collected_by');
    }
}
