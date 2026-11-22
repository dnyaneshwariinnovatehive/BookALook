<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\ServiceProvider;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * The salon block on each booking feeds the customer app's Upcoming and Book
 * again cards (photo) and the booking card's call and directions buttons. It
 * used to load only id, name and address, so all of those were always empty.
 */
class CustomerBookingSalonCardTest extends TestCase
{
    use DatabaseTransactions;

    public function test_a_booking_carries_the_salon_photo_phone_and_position(): void
    {
        $provider = ServiceProvider::with('salon')->where('is_active', true)->first();
        $customer = User::where('role', 'customer')->first();
        if (! $provider || ! $provider->salon || ! $customer) {
            $this->markTestSkipped('needs a seeded salon with staff and a customer');
        }

        $salon = $provider->salon;
        $salon->forceFill([
            'cover_photo_url' => 'https://example.test/storage/salons/cover.jpg',
            'phone_num' => '9876500000',
            'latitude' => 18.5204,
            'longitude' => 73.8567,
        ])->save();

        $appointment = Appointment::create([
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
        ]);

        $body = $this->actingAs($customer, 'sanctum')
            ->getJson('/api/customer/appointments')
            ->assertOk()
            ->json();

        $card = collect(array_merge($body['upcoming'] ?? [], $body['action_required'] ?? [], $body['past'] ?? []))
            ->firstWhere('id', $appointment->id);

        $this->assertNotNull($card, 'the booking is missing from the list');
        $this->assertSame('https://example.test/storage/salons/cover.jpg', $card['salon']['cover_photo_url']);
        $this->assertSame('9876500000', $card['salon']['phone']);
        $this->assertEqualsWithDelta(18.5204, $card['salon']['latitude'], 0.0001);
    }
}
