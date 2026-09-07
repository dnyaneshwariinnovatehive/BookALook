<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\AppointmentService as AppointmentLine;
use App\Models\AppointmentServiceAddition;
use App\Models\Salon;
use App\Models\Service;
use App\Models\ServiceProvider;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * Extras added while the customer is in the chair.
 *
 * The point of the feature is that nothing overwrites the original booking and
 * commission follows whoever actually delivered each line — including when a
 * second staff member does the extra.
 *
 * Runs in a transaction so it can use the development database without
 * leaving anything behind.
 */
class DynamicBillAdjustmentTest extends TestCase
{
    use DatabaseTransactions;

    public function test_an_extra_is_a_separate_line_and_the_total_recalculates(): void
    {
        [$salon, $admin, $provider] = $this->fixture(minServices: 2);
        $booked = $provider->services->first();
        $extra = $provider->services->skip(1)->first();

        $appointment = $this->givenInProgress($salon, $provider, $booked);

        $response = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/add-service", [
                'service_id' => $extra->id,
            ])
            ->assertStatus(201)
            ->json();

        // The original booked line is untouched.
        $this->assertSame(1, $appointment->services()->count());
        $this->assertEquals(1000.0, (float) $appointment->services()->first()->price_at_booking);

        // The extra is its own row with full provenance.
        $addition = AppointmentServiceAddition::where('appointment_id', $appointment->id)->first();
        $this->assertNotNull($addition);
        $this->assertSame($extra->id, $addition->service_id);
        $this->assertSame($admin->id, $addition->added_by);
        $this->assertSame($provider->id, $addition->provider_id);
        $this->assertEquals((float) $extra->price, (float) $addition->price_at_addition);
        $this->assertGreaterThan(0, (int) $addition->duration_minutes_at_addition);
        $this->assertNotNull($addition->added_at);
        $this->assertSame('active', $addition->status);

        // The bill itemises booked and added separately.
        $lines = collect($response['bill']['lines']);
        $this->assertCount(2, $lines);
        $this->assertCount(1, $lines->where('added_mid_appointment', false));

        $addedLine = $lines->firstWhere('added_mid_appointment', true);
        $this->assertNotNull($addedLine);
        $this->assertSame($admin->name, $addedLine['added_by_name']);
        $this->assertNotNull($addedLine['provider_name']);

        // Totals recalculate; the advance stays where it was.
        $appointment->refresh();
        $expected = round(1000.0 + (float) $extra->price, 2);
        $this->assertEquals($expected, (float) $appointment->total_amount);
        $this->assertEquals(300.0, (float) $appointment->advance_amount);
        $this->assertEquals($expected - 300.0, (float) $appointment->balance_amount);
        $this->assertEquals($expected - 300.0, $response['bill']['balance_due']);
    }

    public function test_an_extra_can_be_credited_to_a_different_provider(): void
    {
        [$salon, $admin, $provider, $other] = $this->fixture(minServices: 2, needsSecondProvider: true);
        $booked = $provider->services->first();
        $extra = $provider->services->skip(1)->first();

        $appointment = $this->givenInProgress($salon, $provider, $booked);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/add-service", [
                'service_id' => $extra->id,
                'provider_id' => $other->id,
            ])
            ->assertStatus(201);

        $addition = AppointmentServiceAddition::where('appointment_id', $appointment->id)->first();
        $this->assertSame($other->id, $addition->provider_id);

        // Settle, and each line's commission goes to the person who did it.
        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/collect-payment", [
                'payment_mode' => 'cash',
            ])
            ->assertStatus(200);

        $bookedLine = $appointment->services()->first();
        $addition->refresh();

        $this->assertEquals(
            (float) $provider->commission_percentage,
            (float) $bookedLine->commission_percentage_snapshot
        );
        $this->assertEquals(
            (float) $other->commission_percentage,
            (float) $addition->commission_percentage_snapshot
        );
        $this->assertEquals(
            round((float) $addition->price_at_addition * (float) $other->commission_percentage / 100, 2),
            (float) $addition->commission_amount
        );
    }

    public function test_a_settled_extra_reads_the_same_as_a_booked_line(): void
    {
        [$salon, $admin, $provider] = $this->fixture(minServices: 2);
        $booked = $provider->services->first();
        $extra = $provider->services->skip(1)->first();

        $appointment = $this->givenInProgress($salon, $provider, $booked);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/add-service", [
                'service_id' => $extra->id,
            ])
            ->assertStatus(201);

        $addition = AppointmentServiceAddition::where('appointment_id', $appointment->id)->first();
        $this->assertSame(AppointmentServiceAddition::STATUS_ACTIVE, $addition->status);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/collect-payment", [
                'payment_mode' => 'cash',
            ])
            ->assertStatus(200);

        // The booked line settles to 'completed'; an extra has to say the same
        // thing rather than sitting at 'active' forever.
        $this->assertSame('completed', $appointment->services()->first()->line_status);
        $this->assertSame(AppointmentServiceAddition::STATUS_COMPLETED, $addition->fresh()->status);

        // Settling must not drop it off the bill...
        $bill = $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/bill")
            ->assertStatus(200)
            ->json('bill');

        $this->assertCount(2, $bill['lines']);
        $this->assertEquals(
            round(1000.0 + (float) $extra->price, 2),
            $bill['total']
        );

        // ...nor out of the provider's commission.
        $this->assertGreaterThan(
            0,
            app(\App\Services\PayrollService::class)
                ->commissionEarned($provider->id, \Carbon\Carbon::today())
        );
    }

    public function test_a_voided_extra_stays_off_the_bill_when_it_settles(): void
    {
        [$salon, $admin, $provider] = $this->fixture(minServices: 2);
        $booked = $provider->services->first();
        $extra = $provider->services->skip(1)->first();

        $appointment = $this->givenInProgress($salon, $provider, $booked);

        $added = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/add-service", [
                'service_id' => $extra->id,
            ])
            ->assertStatus(201)
            ->json();

        $additionId = collect($added['bill']['lines'])->firstWhere('added_mid_appointment', true)['id'];

        $this->actingAs($admin, 'sanctum')
            ->deleteJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/additions/{$additionId}")
            ->assertStatus(200);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/collect-payment", [
                'payment_mode' => 'cash',
            ])
            ->assertStatus(200);

        // Voided is the one status that does not settle — it was taken off.
        $this->assertSame(
            AppointmentServiceAddition::STATUS_VOIDED,
            AppointmentServiceAddition::find($additionId)->status
        );
        $this->assertEquals(1000.0, (float) $appointment->fresh()->final_billed_amount);
    }

    public function test_an_extra_can_be_taken_back_off_before_payment(): void
    {
        [$salon, $admin, $provider] = $this->fixture(minServices: 2);
        $booked = $provider->services->first();
        $extra = $provider->services->skip(1)->first();

        $appointment = $this->givenInProgress($salon, $provider, $booked);

        $added = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/add-service", [
                'service_id' => $extra->id,
            ])
            ->assertStatus(201)
            ->json();

        $additionId = collect($added['bill']['lines'])->firstWhere('added_mid_appointment', true)['id'];

        $this->actingAs($admin, 'sanctum')
            ->deleteJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/additions/{$additionId}")
            ->assertStatus(200);

        $appointment->refresh();
        $this->assertEquals(1000.0, (float) $appointment->total_amount);
        $this->assertEquals(700.0, (float) $appointment->balance_amount);

        // Voided, not deleted — the bill can still explain itself.
        $this->assertSame('voided', AppointmentServiceAddition::find($additionId)->status);
    }

    public function test_the_customer_sees_the_extras_itemised(): void
    {
        [$salon, $admin, $provider] = $this->fixture(minServices: 2);
        $customer = User::where('role', 'customer')->first();
        $booked = $provider->services->first();
        $extra = $provider->services->skip(1)->first();

        $appointment = $this->givenInProgress($salon, $provider, $booked, $customer);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/add-service", [
                'service_id' => $extra->id,
            ])
            ->assertStatus(201);

        $booking = $this->actingAs($customer, 'sanctum')
            ->getJson("/api/customer/appointments/{$appointment->id}")
            ->assertStatus(200)
            ->json('appointment');

        // Booked and added stay in separate lists, with the running split.
        $this->assertCount(1, $booking['services']);
        $this->assertCount(1, $booking['added_services']);
        $this->assertSame($extra->template->name, $booking['added_services'][0]['name']);
        $this->assertNotNull($booking['added_services'][0]['provider_name']);
        $this->assertEquals(1000.0, $booking['booked_total']);
        $this->assertEquals((float) $extra->price, $booking['added_total']);
        $this->assertEquals(1000.0 + (float) $extra->price, $booking['total_amount']);
    }

    public function test_extras_are_rejected_outside_an_in_progress_appointment(): void
    {
        [$salon, $admin, $provider] = $this->fixture(minServices: 2);
        $booked = $provider->services->first();
        $extra = $provider->services->skip(1)->first();

        $appointment = $this->givenInProgress($salon, $provider, $booked);
        $appointment->update(['status' => 'scheduled']);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/add-service", [
                'service_id' => $extra->id,
            ])
            ->assertStatus(422);
    }

    public function test_outsiders_cannot_change_a_bill(): void
    {
        [$salon, , $provider] = $this->fixture(minServices: 2);
        $customer = User::where('role', 'customer')->first();
        $booked = $provider->services->first();
        $extra = $provider->services->skip(1)->first();

        $appointment = $this->givenInProgress($salon, $provider, $booked);

        // The old endpoint had no guard at all: any logged-in user could add a
        // charge to any appointment.
        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/add-service", [
                'service_id' => $extra->id,
            ])
            ->assertStatus(403);
    }

    public function test_a_service_from_another_salon_cannot_be_billed(): void
    {
        [$salon, $admin, $provider] = $this->fixture();
        $booked = $provider->services->first();

        $foreign = Service::where('salon_id', '!=', $salon->id)->first();

        if (! $foreign) {
            $this->markTestSkipped('needs a service belonging to a different salon');
        }

        $appointment = $this->givenInProgress($salon, $provider, $booked);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/add-service", [
                'service_id' => $foreign->id,
            ])
            ->assertStatus(422);
    }

    // ------------------------------------------------------------- fixtures

    /** @return array{0: Salon, 1: User, 2: ServiceProvider, 3: ?ServiceProvider} */
    private function fixture(int $minServices = 1, bool $needsSecondProvider = false): array
    {
        $provider = ServiceProvider::with(['user', 'services.template', 'salon'])
            ->whereHas('services', null, '>=', $minServices)
            ->where('is_active', true)
            ->first();

        if (! $provider || ! $provider->salon || ! $provider->user) {
            $this->markTestSkipped("needs an active provider with at least {$minServices} service(s)");
        }

        $admin = User::find($provider->salon->admin_id);

        if (! $admin) {
            $this->markTestSkipped('needs the salon owner account');
        }

        $other = ServiceProvider::with('user')
            ->where('salon_id', $provider->salon_id)
            ->whereKeyNot($provider->id)
            ->where('is_active', true)
            ->first();

        if ($needsSecondProvider && ! $other) {
            $this->markTestSkipped('needs a second staff member at the salon');
        }

        return [$provider->salon, $admin, $provider, $other];
    }

    private function givenInProgress(
        Salon $salon,
        ServiceProvider $provider,
        Service $service,
        ?User $customer = null
    ): Appointment {
        $appointment = Appointment::create([
            'salon_id' => $salon->id,
            'customer_id' => $customer?->id,
            'appointed_provider_id' => $provider->id,
            'serving_provider_id' => $provider->id,
            'booking_source' => 'online',
            'appointment_date' => Carbon::today()->toDateString(),
            'start_time' => '10:00:00',
            'end_time' => '10:30:00',
            'status' => 'in_progress',
            'payment_option' => 'advance_only',
            'total_amount' => 1000,
            'advance_amount' => 300,
            'balance_amount' => 700,
            'started_at' => now(),
        ]);

        AppointmentLine::create([
            'appointment_id' => $appointment->id,
            'service_id' => $service->id,
            'serving_provider_id' => $provider->id,
            'price_at_booking' => 1000,
            'original_service_price' => $service->price,
            'duration_minutes_at_booking' => 30,
            'line_status' => 'booked',
        ]);

        return $appointment->fresh();
    }
}
