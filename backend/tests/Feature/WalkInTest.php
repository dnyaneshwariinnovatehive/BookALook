<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * Walk-in customers, added by staff and by an admin at the desk.
 *
 * Runs in a transaction so it can use the development database without
 * leaving anything behind.
 */
class WalkInTest extends TestCase
{
    use DatabaseTransactions;

    public function test_a_provider_adds_their_own_walk_in_and_it_starts_immediately(): void
    {
        [$salon, , $provider] = $this->fixture();
        $service = $provider->services->first();

        $response = $this->actingAs($provider->user, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/walk-in", [
                'customer_name' => 'Desk Customer',
                'customer_phone' => '9990001111',
                'gender' => 'Female',
                'services' => [$service->id],
            ])
            ->assertStatus(201)
            ->assertJsonPath('appointment.status', 'in_progress')
            ->json();

        $appointment = Appointment::find($response['appointment']['id']);

        $this->assertSame('walk_in', $appointment->booking_source);
        $this->assertSame('Desk Customer', $appointment->walk_in_customer_name);
        $this->assertNull($appointment->customer_id);
        // Whoever added it is serving it, and the line agrees — salary is paid
        // off the line.
        $this->assertSame($provider->id, $appointment->serving_provider_id);
        $this->assertSame($provider->id, $appointment->services()->first()->serving_provider_id);

        // The bug that made every walk-in 500: duration came from a column that
        // does not exist, so the line could not be written at all.
        $line = $appointment->services()->first();
        $this->assertGreaterThan(0, (int) $line->duration_minutes_at_booking);
        $this->assertSame('booked', $line->line_status);

        // A zero-length appointment is not a real appointment.
        $this->assertNotSame(
            substr($appointment->start_time, 0, 5),
            substr($appointment->end_time, 0, 5)
        );

        // Nothing is prepaid; the whole amount is collected at the counter.
        $this->assertEquals(0.0, (float) $appointment->advance_amount);
        $this->assertEquals(
            (float) $service->price,
            (float) $appointment->total_amount
        );
        $this->assertEquals((float) $service->price, (float) $appointment->balance_amount);
    }

    public function test_an_admin_adds_a_walk_in_and_picks_who_serves_it(): void
    {
        [$salon, $admin, $provider] = $this->fixture();
        $service = $provider->services->first();

        // The admin has no ServiceProvider row of their own — the old endpoint
        // rejected them outright.
        $options = $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/walk-in/options")
            ->assertStatus(200)
            ->json();

        $this->assertTrue($options['can_choose_provider']);
        $this->assertNull($options['default_provider_id']);
        $this->assertContains($provider->id, array_column($options['providers'], 'id'));

        // Services arrive flat and priced, with a real name rather than the
        // grouped shape the old screen mistook for a service list.
        $this->assertNotEmpty($options['services']);
        $offered = collect($options['services'])->firstWhere('id', $service->id);
        $this->assertNotNull($offered);
        $this->assertNotEmpty($offered['name']);
        $this->assertGreaterThan(0, $offered['duration_minutes']);

        $response = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/walk-in", [
                'customer_name' => 'Admin Added',
                'services' => [$service->id],
                'provider_id' => $provider->id,
            ])
            ->assertStatus(201)
            ->json();

        $appointment = Appointment::find($response['appointment']['id']);
        $this->assertSame($provider->id, $appointment->serving_provider_id);
        $this->assertSame($provider->id, $appointment->appointed_provider_id);
    }

    public function test_multiple_services_are_priced_and_timed_together(): void
    {
        [$salon, $admin, $provider] = $this->fixture(minServices: 2);
        $services = $provider->services->take(2);

        $preview = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/walk-in/preview", [
                'services' => $services->pluck('id')->all(),
                'provider_id' => $provider->id,
            ])
            ->assertStatus(200)
            ->json();

        $expectedTotal = round((float) $services->sum('price'), 2);
        $this->assertEquals($expectedTotal, $preview['total']);
        $this->assertGreaterThan(0, $preview['duration_minutes']);

        $response = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/walk-in", [
                'customer_name' => 'Two Services',
                'services' => $services->pluck('id')->all(),
                'provider_id' => $provider->id,
            ])
            ->assertStatus(201)
            ->json();

        $appointment = Appointment::find($response['appointment']['id']);
        $this->assertSame(2, $appointment->services()->count());
        $this->assertEquals($expectedTotal, (float) $appointment->total_amount);
        $this->assertEquals($expectedTotal, $response['bill']['total']);
    }

    public function test_a_clash_is_reported_before_it_is_created_and_can_be_overridden(): void
    {
        [$salon, $admin, $provider] = $this->fixture();
        $service = $provider->services->first();

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/walk-in", [
                'customer_name' => 'First In',
                'services' => [$service->id],
                'provider_id' => $provider->id,
            ])
            ->assertStatus(201);

        $clash = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/walk-in", [
                'customer_name' => 'Same Time',
                'services' => [$service->id],
                'provider_id' => $provider->id,
            ])
            ->assertStatus(409)
            ->json();

        $this->assertNotEmpty($clash['conflicts']);
        $this->assertTrue($clash['can_override']);

        // Squeezing someone in is a normal thing to do — but a decision.
        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/walk-in", [
                'customer_name' => 'Same Time',
                'services' => [$service->id],
                'provider_id' => $provider->id,
                'allow_overlap' => true,
            ])
            ->assertStatus(201)
            ->assertJsonPath('overlapped', true);
    }

    public function test_a_walk_in_booked_for_later_waits_to_be_checked_in(): void
    {
        [$salon, $admin, $provider] = $this->fixture();
        $service = $provider->services->first();

        $later = Carbon::today()->setTime(23, 0)->format('Y-m-d H:i:s');

        $response = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/walk-in", [
                'customer_name' => 'Coming Back',
                'services' => [$service->id],
                'provider_id' => $provider->id,
                'start_time' => $later,
                'allow_overlap' => true,
            ])
            ->assertStatus(201)
            ->assertJsonPath('appointment.status', 'scheduled')
            ->json();

        $appointment = Appointment::find($response['appointment']['id']);
        $this->assertNull($appointment->serving_provider_id);
        $this->assertNull($appointment->started_at);
    }

    public function test_the_walk_in_flows_into_billing(): void
    {
        [$salon, $admin, $provider] = $this->fixture();
        $service = $provider->services->first();

        $created = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/walk-in", [
                'customer_name' => 'Pays At Counter',
                'services' => [$service->id],
                'provider_id' => $provider->id,
            ])
            ->assertStatus(201)
            ->json();

        $id = $created['appointment']['id'];

        // Nothing prepaid, so the whole total is due at the counter.
        $this->assertEquals($created['bill']['total'], $created['bill']['balance_due']);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$id}/collect-payment", [
                'payment_mode' => 'cash',
            ])
            ->assertStatus(200)
            ->assertJsonPath('appointment.status', 'completed');

        $appointment = Appointment::find($id);
        $this->assertEquals(0.0, (float) $appointment->balance_amount);
        $this->assertSame('cash', $appointment->payment_mode);
        // Commission was frozen against the person who did the work.
        $this->assertEquals(
            (float) $provider->commission_percentage,
            (float) $appointment->services()->first()->commission_percentage_snapshot
        );
    }

    public function test_outsiders_cannot_add_walk_ins(): void
    {
        [$salon, , $provider] = $this->fixture();
        $customer = User::where('role', 'customer')->first();

        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/walk-in", [
                'customer_name' => 'Should Fail',
                'services' => [$provider->services->first()->id],
                'provider_id' => $provider->id,
            ])
            ->assertStatus(403);
    }

    public function test_a_service_from_another_salon_is_rejected(): void
    {
        [$salon, $admin, $provider] = $this->fixture();

        $foreign = \App\Models\Service::where('salon_id', '!=', $salon->id)->first();

        if (! $foreign) {
            $this->markTestSkipped('needs a service belonging to a different salon');
        }

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/walk-in", [
                'customer_name' => 'Wrong Salon',
                'services' => [$foreign->id],
                'provider_id' => $provider->id,
            ])
            ->assertStatus(422);
    }

    // ------------------------------------------------------------- fixtures

    /** @return array{0: Salon, 1: User, 2: ServiceProvider} */
    private function fixture(int $minServices = 1): array
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

        return [$provider->salon, $admin, $provider];
    }
}
