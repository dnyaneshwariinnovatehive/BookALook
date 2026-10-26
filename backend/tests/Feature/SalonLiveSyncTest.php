<?php

namespace Tests\Feature;

use App\Jobs\SendSalonSyncJob;
use App\Models\Appointment;
use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Models\User;
use App\Models\UserDevice;
use App\Services\Notifications\PushGateway;
use App\Services\Notifications\PushPayload;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * A booking made or changed in the customer app nudges the salon's partner
 * apps to refresh, with a silent push that shows nothing on screen.
 */
class SalonLiveSyncTest extends TestCase
{
    use DatabaseTransactions;

    public function test_a_new_booking_nudges_the_salon_once(): void
    {
        Queue::fake();
        Cache::flush();
        [$salon, , $provider, $customer] = $this->salon();

        $appointment = $this->appointment($salon, $provider, $customer);
        // The several saves one booking makes collapse into one push.
        $appointment->forceFill(['customer_phone_hash' => 'x'])->save();
        $appointment->forceFill(['status' => 'scheduled'])->save();

        Queue::assertPushed(SendSalonSyncJob::class, 1);
        Queue::assertPushed(SendSalonSyncJob::class, fn ($job) => $job->salonId === $salon->id);
    }

    public function test_a_change_that_moves_nothing_on_screen_sends_nothing(): void
    {
        Queue::fake();
        Cache::flush();
        [$salon, , $provider, $customer] = $this->salon();
        $appointment = $this->appointment($salon, $provider, $customer);

        // Past the de-duplication window, so only the field decides.
        Cache::flush();
        $appointment->forceFill(['qr_generated_at' => now()])->save();

        Queue::assertPushed(SendSalonSyncJob::class, 1);
    }

    public function test_the_push_goes_silently_to_every_partner_phone_at_the_salon(): void
    {
        [$salon, $admin, $provider] = $this->salon();
        $this->device($admin, UserDevice::APP_TYPE_PARTNER);
        $this->device($provider->user, UserDevice::APP_TYPE_PARTNER);
        $this->device(User::find($provider->user_id), UserDevice::APP_TYPE_CUSTOMER);

        $gateway = new class implements PushGateway {
            public array $sent = [];

            public function send(iterable $devices, PushPayload $payload): array
            {
                foreach ($devices as $device) {
                    $this->sent[] = [$device->app_type, $payload];
                }

                return [];
            }
        };

        (new SendSalonSyncJob($salon->id, 'apt-1'))->handle($gateway);

        $this->assertCount(2, $gateway->sent);
        foreach ($gateway->sent as [$appType, $payload]) {
            $this->assertSame(UserDevice::APP_TYPE_PARTNER, $appType);
            $this->assertTrue($payload->silent);
            $this->assertSame('salon_sync', $payload->toDataArray()['type']);
            $this->assertSame($salon->id, $payload->toDataArray()['salon_id']);
        }
    }

    // ------------------------------------------------------------- fixtures

    private function salon(): array
    {
        $uuid = fn () => (string) Str::uuid();
        $phone = fn () => '9' . random_int(100000000, 999999999);

        $admin = User::create(['id' => $uuid(), 'name' => 'Sync Owner', 'phone' => $phone(),
            'password_hash' => 'x', 'role' => 'admin', 'is_active' => true]);
        $staff = User::create(['id' => $uuid(), 'name' => 'Sync Staff', 'phone' => $phone(),
            'password_hash' => 'x', 'role' => 'service_provider', 'is_active' => true]);
        $customer = User::create(['id' => $uuid(), 'name' => 'Sync Customer', 'phone' => $phone(),
            'password_hash' => 'x', 'role' => 'customer', 'is_active' => true]);

        $salon = Salon::create(['id' => $uuid(), 'admin_id' => $admin->id, 'name' => 'Sync Salon',
            'slug' => 'sync-salon-' . Str::random(6), 'address' => '1 Test St', 'status' => 'active',
            'submitted_by' => $admin->id]);

        $provider = ServiceProvider::create(['id' => $uuid(), 'user_id' => $staff->id,
            'salon_id' => $salon->id, 'is_active' => true]);

        return [$salon, $admin, $provider->load('user'), $customer];
    }

    private function appointment(Salon $salon, ServiceProvider $provider, User $customer): Appointment
    {
        return Appointment::create([
            'salon_id' => $salon->id,
            'customer_id' => $customer->id,
            'appointed_provider_id' => $provider->id,
            'booking_source' => 'online',
            'appointment_date' => Carbon::tomorrow()->toDateString(),
            'start_time' => '10:00:00',
            'end_time' => '10:30:00',
            'status' => 'pending_payment',
            'payment_option' => 'advance_only',
            'total_amount' => 1000,
            'advance_amount' => 300,
            'balance_amount' => 700,
        ]);
    }

    private function device(User $user, string $appType): void
    {
        UserDevice::create([
            'user_id' => $user->id,
            'app_type' => $appType,
            'platform' => UserDevice::PLATFORM_ANDROID,
            'push_token' => 'token-' . Str::random(12),
            'app_version' => '1.0.0',
            'is_active' => true,
        ]);
    }
}
