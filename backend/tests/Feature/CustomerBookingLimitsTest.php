<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\PlatformPolicySetting;
use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Models\User;
use App\Services\CustomerStandingService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Str;
use Tests\Feature\Concerns\ActivatesSalons;
use Tests\TestCase;

/**
 * SuperAdmin's limits on customer cancellations and no-shows: counted across
 * the platform, consecutively or in total, with block / full payment / warn
 * at the limit, lifting after a set time or when SuperAdmin clears it.
 */
class CustomerBookingLimitsTest extends TestCase
{
    use ActivatesSalons;
    use DatabaseTransactions;

    private User $customer;
    private Salon $salon;
    private ServiceProvider $provider;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-10-27 12:00:00');

        $this->customer = $this->user('customer');
        $owner = $this->user('admin');
        $this->salon = $this->activateSalon(Salon::create([
            'id' => (string) Str::uuid(), 'admin_id' => $owner->id, 'name' => 'Limits Salon',
            'slug' => 'limits-' . Str::random(6), 'address' => 'x', 'status' => 'active', 'submitted_by' => $owner->id,
        ]));
        $this->provider = ServiceProvider::create(['user_id' => $this->user('service_provider')->id, 'salon_id' => $this->salon->id, 'is_active' => true]);
    }

    private function user(string $role): User
    {
        return User::create([
            'id' => (string) Str::uuid(), 'name' => ucfirst($role) . ' ' . Str::random(3), 'phone' => '9' . random_int(100000000, 999999999),
            'password_hash' => 'x', 'role' => $role, 'is_active' => true,
        ]);
    }

    private function policy(array $values): void
    {
        foreach ($values as $key => $value) {
            PlatformPolicySetting::updateOrCreate(
                ['setting_key' => $key],
                ['setting_value' => (string) $value, 'data_type' => is_int($value) ? 'integer' : 'string', 'updated_by' => $this->customer->id],
            );
        }
    }

    /** Oldest first: each call is one day after the last. */
    private function history(array $outcomes): void
    {
        $day = Carbon::today()->subDays(count($outcomes) + 1);
        foreach ($outcomes as $outcome) {
            $day = $day->copy()->addDay();
            [$status, $by] = match ($outcome) {
                'cancel' => ['cancelled', 'customer'],
                'salon_cancel' => ['cancelled', 'salon'],
                'no_show' => ['no_show', null],
                default => ['completed', null],
            };
            Appointment::create([
                'salon_id' => $this->salon->id, 'customer_id' => $this->customer->id,
                'appointed_provider_id' => $this->provider->id, 'booking_source' => 'online',
                'appointment_date' => $day->toDateString(), 'start_time' => '10:00:00', 'end_time' => '10:30:00',
                'status' => $status, 'cancelled_by' => $by, 'cancelled_at' => $by ? $day : null,
                'payment_option' => 'advance_only', 'total_amount' => 500, 'advance_amount' => 100, 'balance_amount' => 400,
            ]);
        }
    }

    private function standing(): array
    {
        return app(CustomerStandingService::class)->standing($this->customer->fresh());
    }

    public function test_no_limits_by_default(): void
    {
        $this->history(['cancel', 'cancel', 'cancel', 'no_show']);
        $this->assertFalse($this->standing()['restricted']);
    }

    public function test_total_counts_every_cancellation_but_not_the_salons(): void
    {
        $this->policy(['customer_cancellation_limit' => 3, 'customer_cancellation_count_mode' => 'total', 'customer_limit_release_days' => 0]);

        $this->history(['cancel', 'done', 'cancel', 'salon_cancel']);
        $this->assertSame(2, $this->standing()['cancellations']['count']);
        $this->assertFalse($this->standing()['restricted']);

        $this->history(['cancel']);
        $this->assertTrue($this->standing()['restricted']);
        $this->assertSame('block', $this->standing()['action']);
    }

    public function test_consecutive_is_reset_by_a_completed_visit(): void
    {
        $this->policy(['customer_no_show_limit' => 2, 'customer_no_show_count_mode' => 'consecutive', 'customer_limit_release_days' => 0]);

        $this->history(['no_show', 'done', 'no_show']);
        $this->assertSame(1, $this->standing()['no_shows']['count']);
        $this->assertFalse($this->standing()['restricted']);

        $this->history(['no_show']);
        $this->assertTrue($this->standing()['restricted']);
    }

    public function test_the_look_back_window_and_auto_release(): void
    {
        $this->policy([
            'customer_cancellation_limit' => 2, 'customer_cancellation_count_mode' => 'total',
            'customer_limit_window_days' => 0, 'customer_limit_release_days' => 10,
        ]);
        $this->history(['cancel', 'cancel']); // last one yesterday

        $s = $this->standing();
        $this->assertTrue($s['restricted']);
        $this->assertSame(Carbon::yesterday()->addDays(10)->toDateString(), $s['releases_on']);

        Carbon::setTestNow(Carbon::now()->addDays(10));
        $this->assertFalse($this->standing()['restricted'], 'lifted after the release period');
    }

    public function test_block_stops_booking_and_superadmin_can_clear_it(): void
    {
        $this->policy(['customer_cancellation_limit' => 1, 'customer_limit_action' => 'block', 'customer_limit_release_days' => 0]);
        $this->history(['cancel']);

        $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/appointments/book", [
                'date' => Carbon::tomorrow()->toDateString(), 'time' => '11:00',
            ])
            ->assertStatus(403)
            ->assertJsonPath('booking_restricted', true);

        $this->actingAs($this->customer, 'sanctum')
            ->getJson('/api/customer/booking-standing')
            ->assertOk()
            ->assertJsonPath('standing.restricted', true);

        $admin = $this->user('superadmin');
        $this->actingAs($admin, 'sanctum')
            ->getJson("/api/superadmin/customers/{$this->customer->id}")
            ->assertOk()
            ->assertJsonPath('booking_standing.restricted', true);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/superadmin/customers/{$this->customer->id}/reset-booking-standing")
            ->assertOk()
            ->assertJsonPath('booking_standing.restricted', false);

        $this->assertFalse($this->standing()['restricted']);
    }

    public function test_warn_and_full_payment_do_not_block(): void
    {
        $this->policy(['customer_no_show_limit' => 1, 'customer_limit_action' => 'full_payment', 'customer_limit_release_days' => 0]);
        $this->history(['no_show']);

        $s = $this->standing();
        $this->assertTrue($s['restricted']);
        $this->assertSame('full_payment', $s['action']);
        $this->assertStringContainsString('full amount', $s['message']);

        // Not blocked: the request gets past the limit check to the cart check.
        $this->actingAs($this->customer, 'sanctum')
            ->postJson("/api/customer/salons/{$this->salon->id}/appointments/book", [
                'date' => Carbon::tomorrow()->toDateString(), 'time' => '11:00',
            ])
            ->assertStatus(400)
            ->assertJsonPath('message', 'Cart is empty.');
    }

    public function test_superadmin_saves_the_limits_from_policy(): void
    {
        $this->actingAs($this->user('superadmin'), 'sanctum')
            ->putJson('/api/superadmin/settings/policy', [
                'customer_cancellation_limit' => 3,
                'customer_cancellation_count_mode' => 'consecutive',
                'customer_no_show_limit' => 2,
                'customer_no_show_count_mode' => 'total',
                'customer_limit_action' => 'warn',
                'customer_limit_window_days' => 180,
                'customer_limit_release_days' => 0,
            ])
            ->assertOk();

        $settings = app(CustomerStandingService::class)->settings();
        $this->assertSame(3, $settings['customer_cancellation_limit']);
        $this->assertSame('consecutive', $settings['customer_cancellation_count_mode']);
        $this->assertSame('warn', $settings['customer_limit_action']);
        $this->assertSame(0, $settings['customer_limit_release_days']);

        $this->actingAs($this->user('superadmin'), 'sanctum')
            ->putJson('/api/superadmin/settings/policy', ['customer_limit_action' => 'ban'])
            ->assertStatus(422);
    }
}
