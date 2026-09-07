<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\AppointmentService as AppointmentLine;
use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * QR check-in through to payment: scan, start (possibly under a different
 * staff member), bill, collect.
 *
 * Runs in a transaction so it can use the development database without
 * leaving anything behind.
 */
class AppointmentCheckInTest extends TestCase
{
    use DatabaseTransactions;

    public function test_a_provider_scans_and_starts_their_own_customer(): void
    {
        [$salon, , $customer, $provider] = $this->fixture();
        $staffUser = $provider->user;

        [$appointment, $token] = $this->givenBookingWithQr($salon, $customer, $provider);

        $resolved = $this->actingAs($staffUser, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/check-in/resolve", ['qr_token' => $token])
            ->assertStatus(200)
            ->json();

        $this->assertSame($appointment->id, $resolved['appointment']['id']);
        $this->assertTrue($resolved['can_start']);
        $this->assertSame($provider->id, $resolved['default_serving_provider_id']);
        $this->assertEquals(1000.0, $resolved['bill']['total']);
        $this->assertEquals(700.0, $resolved['bill']['balance_due']);

        $this->actingAs($staffUser, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/start", [
                'qr_token' => $token,
            ])
            ->assertStatus(200)
            ->assertJsonPath('appointment.status', 'in_progress')
            ->assertJsonPath('appointment.verification_method', 'qr');

        $appointment->refresh();
        $this->assertSame($provider->id, $appointment->serving_provider_id);
        $this->assertNotNull($appointment->started_at);
    }

    public function test_an_admin_can_hand_the_job_to_a_different_provider(): void
    {
        [$salon, $admin, $customer, $provider, $other] = $this->fixture(needsSecondProvider: true);

        [$appointment, $token] = $this->givenBookingWithQr($salon, $customer, $provider);

        $resolved = $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/check-in/resolve", ['qr_token' => $token])
            ->assertStatus(200)
            ->json();

        // The customer's choice is offered first, but everyone is selectable.
        $this->assertSame($provider->id, $resolved['providers'][0]['id']);
        $this->assertTrue($resolved['providers'][0]['is_booked_provider']);
        $this->assertContains($other->id, array_column($resolved['providers'], 'id'));

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/start", [
                'qr_token' => $token,
                'serving_provider_id' => $other->id,
            ])
            ->assertStatus(200)
            ->assertJsonPath('appointment.serving_provider_id', $other->id);

        $appointment->refresh();

        // The appointment moved...
        $this->assertSame($other->id, $appointment->serving_provider_id);
        // ...and so did the line the salary is paid off, which is the point.
        $this->assertSame($other->id, $appointment->services()->first()->serving_provider_id);
        // The original booking is still on record.
        $this->assertSame($provider->id, $appointment->appointed_provider_id);
    }

    public function test_collecting_payment_settles_the_bill_and_snapshots_commission(): void
    {
        [$salon, $admin, $customer, $provider] = $this->fixture();

        [$appointment, $token] = $this->givenBookingWithQr($salon, $customer, $provider);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/start", [
                'qr_token' => $token,
            ])
            ->assertStatus(200);

        $bill = $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/bill")
            ->assertStatus(200)
            ->json('bill');

        $this->assertEquals(1000.0, $bill['total']);
        $this->assertEquals(300.0, $bill['advance_paid']);
        $this->assertEquals(700.0, $bill['balance_due']);
        $this->assertCount(1, $bill['lines']);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/collect-payment", [
                'payment_mode' => 'upi',
            ])
            ->assertStatus(200)
            ->assertJsonPath('appointment.status', 'completed');

        $appointment->refresh();
        $this->assertEquals(0.0, (float) $appointment->balance_amount);
        $this->assertEquals(1000.0, (float) $appointment->final_billed_amount);
        $this->assertSame('upi', $appointment->payment_mode);
        $this->assertSame($admin->id, $appointment->payment_collected_by);

        // Only the balance is charged — the advance is not taken twice.
        $this->assertDatabaseHas('payments', [
            'appointment_id' => $appointment->id,
            'amount' => 700.0,
            'payment_type' => 'balance',
            'payment_mode' => 'upi',
            'status' => 'success',
        ]);

        // Commission frozen against the provider who actually served it.
        $line = $appointment->services()->first();
        $this->assertSame($provider->id, $line->serving_provider_id);
        $this->assertEquals(
            (float) $provider->commission_percentage,
            (float) $line->commission_percentage_snapshot
        );
        $this->assertEquals(
            round(1000.0 * (float) $provider->commission_percentage / 100, 2),
            (float) $line->commission_amount
        );
        $this->assertSame('completed', $line->line_status);
    }

    public function test_a_session_can_be_started_without_a_scan_and_is_recorded_as_manual(): void
    {
        [$salon, $admin, $customer, $provider] = $this->fixture();

        [$appointment] = $this->givenBookingWithQr($salon, $customer, $provider);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/start", [
                'manual' => true,
                'reason' => 'Customer phone battery dead',
            ])
            ->assertStatus(200)
            ->assertJsonPath('appointment.verification_method', 'manual');

        $appointment->refresh();
        $this->assertSame('Customer phone battery dead', $appointment->manual_check_in_reason);
        // The token is burned so it cannot be replayed after a manual start.
        $this->assertNull($appointment->qr_token_hash);
    }

    public function test_a_qr_from_another_booking_is_rejected(): void
    {
        [$salon, $admin, $customer, $provider] = $this->fixture();

        [$first] = $this->givenBookingWithQr($salon, $customer, $provider);
        [, $otherToken] = $this->givenBookingWithQr($salon, $customer, $provider, startTime: '15:00:00');

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$first->id}/start", [
                'qr_token' => $otherToken,
            ])
            ->assertStatus(422)
            ->assertJsonPath('message', 'That QR code is for a different booking.');
    }

    public function test_outsiders_cannot_check_in_or_take_money(): void
    {
        [$salon, , $customer, $provider] = $this->fixture();
        [$appointment, $token] = $this->givenBookingWithQr($salon, $customer, $provider);

        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/check-in/resolve", ['qr_token' => $token])
            ->assertStatus(403);

        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/collect-payment", [
                'payment_mode' => 'cash',
            ])
            ->assertStatus(403);

        // The legacy id-only endpoint had no guard at all.
        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/partner/appointments/{$appointment->id}/complete")
            ->assertStatus(403);
    }

    public function test_payment_cannot_be_collected_before_the_session_starts(): void
    {
        [$salon, $admin, $customer, $provider] = $this->fixture();
        [$appointment] = $this->givenBookingWithQr($salon, $customer, $provider);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}/collect-payment", [
                'payment_mode' => 'cash',
            ])
            ->assertStatus(422);
    }

    // ------------------------------------------------------------- fixtures

    /** @return array{0: Salon, 1: User, 2: User, 3: ServiceProvider, 4: ?ServiceProvider} */
    private function fixture(bool $needsSecondProvider = false): array
    {
        $provider = ServiceProvider::with(['user', 'services', 'salon'])
            ->whereHas('services')
            ->first();
        $customer = User::where('role', 'customer')->first();

        if (! $provider || ! $customer || ! $provider->salon || ! $provider->user) {
            $this->markTestSkipped('needs a seeded salon with staff, services and a customer');
        }

        $salon = $provider->salon;
        $admin = User::find($salon->admin_id);

        if (! $admin) {
            $this->markTestSkipped('needs the salon owner account');
        }

        $other = ServiceProvider::with('user')
            ->where('salon_id', $salon->id)
            ->whereKeyNot($provider->id)
            ->where('is_active', true)
            ->first();

        if ($needsSecondProvider && ! $other) {
            $this->markTestSkipped('needs a second staff member at the salon');
        }

        return [$salon, $admin, $customer, $provider, $other];
    }

    /** @return array{0: Appointment, 1: string} */
    private function givenBookingWithQr(
        Salon $salon,
        User $customer,
        ServiceProvider $provider,
        string $startTime = '10:00:00'
    ): array {
        $service = $provider->services->first();
        $token = 'test-' . bin2hex(random_bytes(8));

        $appointment = Appointment::create([
            'salon_id' => $salon->id,
            'customer_id' => $customer->id,
            'appointed_provider_id' => $provider->id,
            'booking_source' => 'online',
            // Today, so the "too early to start" guard does not fire.
            'appointment_date' => Carbon::today()->toDateString(),
            'start_time' => $startTime,
            'end_time' => '23:30:00',
            'status' => 'scheduled',
            'payment_option' => 'advance_only',
            'total_amount' => 1000,
            'advance_amount' => 300,
            'balance_amount' => 700,
            'qr_token_hash' => hash('sha256', $token),
            'qr_generated_at' => now(),
            'qr_expires_at' => now()->addHours(2),
        ]);

        AppointmentLine::create([
            'appointment_id' => $appointment->id,
            'service_id' => $service->id,
            'price_at_booking' => 1000,
            'original_service_price' => $service->price,
            'duration_minutes_at_booking' => 30,
            'line_status' => 'booked',
        ]);

        return [$appointment->fresh(), $token];
    }
}
