<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\AppointmentService as AppointmentLine;
use App\Models\Notification;
use App\Models\Salon;
use App\Models\SalonWorkingHour;
use App\Models\ServiceProvider;
use App\Models\User;
use App\Models\WhatsAppMessage;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * Emergency day closure, end to end: admin closes a day -> the customer is
 * notified, keeps their money, and can rebook for free.
 *
 * Runs in a transaction so it can use the development database without
 * leaving anything behind.
 */
class DayClosureMassRescheduleTest extends TestCase
{
    use DatabaseTransactions;

    public function test_closing_a_day_releases_bookings_and_notifies_customers(): void
    {
        [$salon, $admin, $customer, $provider, $date] = $this->fixture();

        $appointment = $this->givenBooking($salon, $customer, $provider, $date, advance: 300.0);

        $preview = $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/closures/preview?date={$date}")
            ->assertStatus(200)
            ->json();

        $this->assertGreaterThanOrEqual(1, $preview['affected_count']);
        $this->assertGreaterThanOrEqual(300.0, $preview['advance_carried_forward']);

        $response = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/closures", [
                'date' => $date,
                'reason' => 'Burst water pipe',
            ])
            ->assertStatus(201)
            ->json();

        $this->assertGreaterThanOrEqual(1, $response['released_count']);

        $appointment->refresh();
        $this->assertSame('awaiting_reschedule', $appointment->status);
        $this->assertSame('salon', $appointment->cancelled_by);
        $this->assertNotNull($appointment->salon_closure_id);

        // The money is untouched — nothing forfeited, nothing refunded yet.
        $this->assertEquals(300.0, (float) $appointment->advance_amount);
        $this->assertSame(1, $appointment->services()->count());

        // In-app notification carrying a reschedule deeplink.
        $notification = Notification::where('related_appointment_id', $appointment->id)
            ->where('type', 'salon_closure')
            ->first();
        $this->assertNotNull($notification, 'customer was not notified in-app');
        $this->assertSame('reschedule_appointment', $notification->data['action']);
        $this->assertStringContainsString($appointment->id, $notification->data['deeplink']);

        // WhatsApp mirror is queued in the outbox, not silently dropped.
        $this->assertDatabaseHas('whatsapp_messages', [
            'related_appointment_id' => $appointment->id,
            'status' => WhatsAppMessage::STATUS_QUEUED,
        ]);
    }

    public function test_the_customer_sees_it_as_action_required_and_can_rebook_free(): void
    {
        [$salon, $admin, $customer, $provider, $date] = $this->fixture();

        $appointment = $this->givenBooking($salon, $customer, $provider, $date, advance: 300.0);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/closures", ['date' => $date, 'reason' => 'Power cut'])
            ->assertStatus(201);

        $bookings = $this->actingAs($customer, 'sanctum')
            ->getJson('/api/customer/appointments')
            ->assertStatus(200)
            ->json();

        $flagged = collect($bookings['action_required'])->firstWhere('id', $appointment->id);
        $this->assertNotNull($flagged, 'released booking is missing from action_required');
        $this->assertTrue($flagged['needs_reschedule']);
        $this->assertTrue($flagged['free_reschedule']);
        $this->assertTrue($flagged['can_reschedule']);
        $this->assertEquals(300.0, $flagged['advance_paid']);
        // Cancelling instead returns everything, because this was not their doing.
        $this->assertEquals(300.0, $flagged['refundable_advance']);
        $this->assertEquals(0.0, $flagged['forfeited_advance']);

        // A new day, and the freed slot is bookable again.
        $newDate = $this->nextOpenDateAfter($salon->id, $date);
        $this->assertNotNull($newDate);

        $options = $this->actingAs($customer, 'sanctum')
            ->getJson("/api/customer/appointments/{$appointment->id}/reschedule-options?date={$newDate}&provider_id={$provider->id}")
            ->assertStatus(200)
            ->json();

        $this->assertTrue($options['free_reschedule']);

        $slot = collect($options['slots'])->firstWhere('available', true);
        $this->assertNotNull($slot, 'no free slot on the replacement date');

        $result = $this->actingAs($customer, 'sanctum')
            ->postJson("/api/customer/appointments/{$appointment->id}/reschedule", [
                'date' => $newDate,
                'time' => $slot['time'],
                'provider_id' => $provider->id,
            ])
            ->assertStatus(200)
            ->json();

        // Same money, new day, no re-payment.
        $this->assertEquals(300.0, $result['appointment']['advance_paid']);
        $this->assertSame($newDate, $result['appointment']['appointment_date']);
        $this->assertSame('scheduled', $result['appointment']['status']);
        $this->assertCount(1, $result['appointment']['services']);

        $appointment->refresh();
        $this->assertSame('rescheduled', $appointment->status);

        // The forced move must not count towards the same-day abuse penalty.
        $this->assertSame(
            0,
            app(\App\Services\BookingPolicyService::class)->sameDayChangeCount($customer->id, $date)
        );
    }

    public function test_a_closed_day_stops_taking_new_bookings(): void
    {
        [$salon, $admin, , $provider, $date] = $this->fixture();

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/closures", ['date' => $date])
            ->assertStatus(201);

        $result = app(\App\Services\AvailabilityService::class)
            ->generateSlots($salon->id, $date, [$provider->id], 30);

        $this->assertTrue($result['closed']);
        $this->assertSame([], $result['slots']);
    }

    public function test_closing_the_same_day_twice_is_safe(): void
    {
        [$salon, $admin, $customer, $provider, $date] = $this->fixture();

        $this->givenBooking($salon, $customer, $provider, $date, advance: 100.0);

        $first = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/closures", ['date' => $date, 'reason' => 'Flood'])
            ->assertStatus(201)
            ->json();

        // A booking that slipped in between the two runs must still be caught,
        // and the unique (salon_id, closed_date) index must not blow up.
        $late = $this->givenBooking($salon, $customer, $provider, $date, advance: 50.0);

        $second = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/closures", ['date' => $date])
            ->assertStatus(201)
            ->json();

        $this->assertGreaterThanOrEqual(1, $first['released_count']);
        $this->assertSame(1, $second['released_count'], 'the late booking should have been picked up');
        $this->assertSame('awaiting_reschedule', $late->fresh()->status);

        $this->assertSame(
            1,
            \App\Models\SalonClosure::where('salon_id', $salon->id)
                ->whereDate('closed_date', $date)
                ->count()
        );
    }

    public function test_reopening_a_day_leaves_released_bookings_with_their_customers(): void
    {
        [$salon, $admin, $customer, $provider, $date] = $this->fixture();

        $appointment = $this->givenBooking($salon, $customer, $provider, $date, advance: 100.0);

        $closure = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/closures", ['date' => $date])
            ->assertStatus(201)
            ->json('closure');

        $response = $this->actingAs($admin, 'sanctum')
            ->deleteJson("/api/partner/salons/{$salon->id}/closures/{$closure['id']}")
            ->assertStatus(200)
            ->json();

        $this->assertGreaterThanOrEqual(1, $response['still_awaiting_reschedule']);

        // The day takes bookings again...
        $slots = app(\App\Services\AvailabilityService::class)
            ->generateSlots($salon->id, $date, [$provider->id], 30);
        $this->assertFalse($slots['closed']);

        // ...but the customer keeps their entitlement, since they were told.
        $appointment->refresh();
        $this->assertSame('awaiting_reschedule', $appointment->status);
        $this->assertEquals(100.0, (float) $appointment->advance_amount);

        $window = app(\App\Services\BookingPolicyService::class)->rescheduleWindow($appointment);
        $this->assertTrue($window['allowed']);
        $this->assertTrue($window['free_reschedule']);
    }

    public function test_only_the_owning_admin_can_close_a_day(): void
    {
        [$salon, , , , $date] = $this->fixture();

        $outsider = User::where('role', 'admin')
            ->whereKeyNot($salon->admin_id)
            ->first()
            ?? User::where('role', 'customer')->first();

        $this->actingAs($outsider, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/closures", ['date' => $date])
            ->assertStatus(403);
    }

    // ------------------------------------------------------------- fixtures

    /** @return array{0: Salon, 1: User, 2: User, 3: ServiceProvider, 4: string} */
    private function fixture(): array
    {
        $provider = ServiceProvider::with(['user', 'services', 'salon'])->whereHas('services')->first();
        $customer = User::where('role', 'customer')->first();

        if (! $provider || ! $customer || ! $provider->salon) {
            $this->markTestSkipped('needs a seeded salon with staff, services and a customer');
        }

        $salon = $provider->salon;
        $admin = User::find($salon->admin_id);

        if (! $admin) {
            $this->markTestSkipped('needs the salon owner account');
        }

        $date = $this->nextOpenDateAfter($salon->id, Carbon::today()->toDateString());

        if (! $date) {
            $this->markTestSkipped('needs a day the salon is open');
        }

        return [$salon, $admin, $customer, $provider, $date];
    }

    private function nextOpenDateAfter(string $salonId, string $after): ?string
    {
        $cursor = Carbon::parse($after);

        for ($i = 1; $i <= 14; $i++) {
            $date = (clone $cursor)->addDays($i);

            $hours = SalonWorkingHour::where('salon_id', $salonId)
                ->where('day_of_week', $date->dayOfWeek)
                ->first();

            $closed = \App\Models\SalonClosure::where('salon_id', $salonId)
                ->whereDate('closed_date', $date->toDateString())
                ->exists();

            if (! $closed && $hours && ! $hours->is_closed && $hours->open_time && $hours->close_time) {
                return $date->toDateString();
            }
        }

        return null;
    }

    private function givenBooking(
        Salon $salon,
        User $customer,
        ServiceProvider $provider,
        string $date,
        float $advance
    ): Appointment {
        $service = $provider->services->first();

        $appointment = Appointment::create([
            'salon_id' => $salon->id,
            'customer_id' => $customer->id,
            'appointed_provider_id' => $provider->id,
            'booking_source' => 'online',
            'appointment_date' => $date,
            'start_time' => '12:00:00',
            'end_time' => '12:30:00',
            'status' => 'scheduled',
            'payment_option' => 'advance_only',
            'total_amount' => 1000,
            'advance_amount' => $advance,
            'balance_amount' => 1000 - $advance,
        ]);

        AppointmentLine::create([
            'appointment_id' => $appointment->id,
            'service_id' => $service->id,
            'price_at_booking' => 1000,
            'original_service_price' => $service->price,
            'duration_minutes_at_booking' => 30,
            'line_status' => 'booked',
        ]);

        return $appointment->fresh();
    }
}
