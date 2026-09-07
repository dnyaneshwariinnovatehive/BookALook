<?php

namespace Tests\Feature;

use App\Models\Cart;
use App\Models\CartItem;
use App\Models\SalonWorkingHour;
use App\Models\ServiceProvider;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

/**
 * The full path a working-hours change travels:
 * admin saves a shift in the partner app -> the customer app's slot grid.
 *
 * Runs inside a transaction so it can use the development database without
 * leaving anything behind.
 */
class ProviderHoursReachCustomerTest extends TestCase
{
    use DatabaseTransactions;

    public function test_narrowing_a_shift_closes_the_customers_slots(): void
    {
        $provider = ServiceProvider::with(['user', 'services'])
            ->whereHas('services')
            ->first();
        $admin = User::where('role', 'admin')->first();
        $customer = User::where('role', 'customer')->first();

        if (! $provider || ! $admin || ! $customer) {
            $this->markTestSkipped('needs a seeded salon with staff, an admin and a customer');
        }

        // A date the salon is actually open, otherwise the grid is empty
        // regardless of the provider's shift.
        $date = $this->firstOpenDate($provider->salon_id);

        if (! $date) {
            $this->markTestSkipped('needs a day the salon is open');
        }

        $service = $provider->services->first();
        $this->givenCartWith($customer->id, $provider->salon_id, $service->id);

        $before = $this->slotsFor($customer, $provider, $date);

        // The admin narrows every day to 11:00-14:00.
        $this->asAdminSetShift($admin, $provider, '11:00:00', '14:00:00');

        $after = $this->slotsFor($customer, $provider, $date);

        fwrite(STDERR, "\ndate: {$date}\n");
        fwrite(STDERR, 'BEFORE: '.$this->render($before)."\n");
        fwrite(STDERR, 'AFTER : '.$this->render($after)."\n");

        $this->assertNotSame(
            $this->render($before),
            $this->render($after),
            'the customer grid did not change after the admin saved a new shift'
        );

        foreach ($after as $slot) {
            if ($slot['time'] < '11:00' && $slot['reason'] !== 'past') {
                $this->assertFalse($slot['available'], "{$slot['time']} should be outside the new shift");
            }
        }
    }

    private function firstOpenDate(string $salonId): ?string
    {
        for ($i = 1; $i <= 7; $i++) {
            $date = Carbon::today()->addDays($i);
            $hours = SalonWorkingHour::where('salon_id', $salonId)
                ->where('day_of_week', $date->dayOfWeek)
                ->first();

            if ($hours && ! $hours->is_closed && $hours->open_time && $hours->close_time) {
                return $date->toDateString();
            }
        }

        return null;
    }

    private function givenCartWith(string $customerId, string $salonId, string $serviceId): void
    {
        Cart::where('customer_id', $customerId)->where('status', 'active')->delete();

        $cart = Cart::create([
            'customer_id' => $customerId,
            'salon_id' => $salonId,
            'status' => 'active',
        ]);

        CartItem::create([
            'cart_id' => $cart->id,
            'service_id' => $serviceId,
            'quantity' => 1,
        ]);
    }

    private function asAdminSetShift(User $admin, ServiceProvider $provider, string $start, string $end): void
    {
        $hours = [];
        for ($day = 0; $day < 7; $day++) {
            $hours[] = [
                'day_of_week' => $day,
                'is_weekly_off' => false,
                'shift_start' => $start,
                'shift_end' => $end,
                'break_start' => null,
                'break_end' => null,
            ];
        }

        $this->actingAs($admin, 'sanctum')
            ->putJson("/api/partner/salons/{$provider->salon_id}/staff/{$provider->id}", [
                'name' => $provider->user->name,
                'phone' => $provider->user->phone,
                'working_hours' => $hours,
            ])
            ->assertStatus(200);
    }

    private function slotsFor(User $customer, ServiceProvider $provider, string $date): array
    {
        $response = $this->actingAs($customer, 'sanctum')->getJson(
            "/api/customer/salons/{$provider->salon_id}/availability?date={$date}&provider_id={$provider->id}"
        );

        $response->assertStatus(200);

        return $response->json('slots') ?? [];
    }

    private function render(array $slots): string
    {
        return implode(' ', array_map(
            fn ($s) => $s['time'].($s['available'] ? '*' : '('.$s['reason'].')'),
            $slots
        ));
    }
}
