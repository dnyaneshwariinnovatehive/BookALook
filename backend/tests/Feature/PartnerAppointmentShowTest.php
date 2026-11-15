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
 * GET /partner/salons/{salon}/appointments/{id}: the single booking the
 * partner app opens when a push notification is tapped. It must follow the
 * same visibility rules as the list.
 */
class PartnerAppointmentShowTest extends TestCase
{
    use DatabaseTransactions;

    public function test_the_owner_gets_the_booking_in_the_list_shape(): void
    {
        [$salon, $admin, $customer, $provider] = $this->fixture();
        $appointment = $this->booking($salon, $customer, $provider);

        $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}")
            ->assertOk()
            ->assertJsonPath('appointment.id', $appointment->id)
            ->assertJsonPath('appointment.customer.id', $customer->id)
            ->assertJsonPath('appointment.is_rescheduled', false)
            ->assertJsonStructure(['appointment' => ['appointed_provider', 'services', 'payment']]);
    }

    public function test_staff_see_their_own_booking_but_not_a_colleagues(): void
    {
        [$salon, , $customer, $provider, $other] = $this->fixture(needsSecondProvider: true);
        $mine = $this->booking($salon, $customer, $provider);
        $theirs = $this->booking($salon, $customer, $other);

        $this->actingAs($provider->user, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments/{$mine->id}")
            ->assertOk();

        $this->actingAs($provider->user, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments/{$theirs->id}")
            ->assertNotFound();
    }

    public function test_another_salons_owner_is_refused(): void
    {
        [$salon, $admin, $customer, $provider] = $this->fixture();
        $appointment = $this->booking($salon, $customer, $provider);

        $stranger = User::where('role', 'admin')->whereKeyNot($admin->id)->first();
        if (! $stranger) {
            $this->markTestSkipped('needs a second salon owner');
        }

        $this->actingAs($stranger, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments/{$appointment->id}")
            ->assertForbidden();
    }

    public function test_a_booking_from_another_salon_is_not_found_under_this_salon(): void
    {
        [$salon, $admin, $customer, $provider] = $this->fixture();
        $otherSalon = Salon::whereKeyNot($salon->id)->first();
        $otherProvider = $otherSalon
            ? ServiceProvider::where('salon_id', $otherSalon->id)->first()
            : null;
        if (! $otherProvider) {
            $this->markTestSkipped('needs a second salon with staff');
        }

        $elsewhere = $this->booking($otherSalon, $customer, $otherProvider);

        $this->actingAs($admin, 'sanctum')
            ->getJson("/api/partner/salons/{$salon->id}/appointments/{$elsewhere->id}")
            ->assertNotFound();
    }

    private function fixture(bool $needsSecondProvider = false): array
    {
        $provider = ServiceProvider::with(['user', 'salon'])->where('is_active', true)->first();
        $customer = User::where('role', 'customer')->first();

        if (! $provider || ! $customer || ! $provider->salon || ! $provider->user) {
            $this->markTestSkipped('needs a seeded salon with staff and a customer');
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

    private function booking(Salon $salon, User $customer, ServiceProvider $provider): Appointment
    {
        return Appointment::create([
            'salon_id' => $salon->id,
            'customer_id' => $customer->id,
            'appointed_provider_id' => $provider->id,
            'booking_source' => 'online',
            'appointment_date' => Carbon::tomorrow()->toDateString(),
            'start_time' => '10:00:00',
            'end_time' => '10:30:00',
            'status' => 'scheduled',
            'payment_option' => 'pay_at_salon',
            'total_amount' => 500,
            'advance_amount' => 0,
            'balance_amount' => 500,
        ])->fresh();
    }
}
