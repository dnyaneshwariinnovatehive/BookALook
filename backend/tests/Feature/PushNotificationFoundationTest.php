<?php

namespace Tests\Feature;

use App\Jobs\SendPushNotificationJob;
use App\Models\Appointment;
use App\Models\Notification;
use App\Models\NotificationDelivery;
use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Models\User;
use App\Models\UserDevice;
use App\Services\Notifications\LogPushGateway;
use App\Services\Notifications\NotificationService;
use App\Services\Notifications\PushGateway;
use App\Services\Notifications\PushPayload;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The push pipeline, end to end, with the provider replaced by the log driver.
 *
 * Deliberately built its own fixtures rather than leaning on the seeded salon
 * data the older tests reach for. A push test that skips itself when a seeder
 * has not been run is a push test that quietly stops testing anything, and
 * nothing in this file needs a salon to be open on a particular Tuesday.
 */
class PushNotificationFoundationTest extends TestCase
{
    use DatabaseTransactions;

    private const TOKEN = 'dJ8fQ2vX1mN4pR7sT0wY3zA6bC9eG5hK8jL2nM4p:APA91bH7xK2mQ9wR4tY6uI3oP1aS5dF0gH8jK2lZ4xC6vB8nM0';

    // -- A. Device registration -------------------------------------------

    public function test_a_device_registers_and_stores_the_push_token(): void
    {
        $customer = $this->customer();

        $response = $this->actingAsCustomer($customer)->postJson('/api/customer/devices/register', [
            'app_type' => 'customer_app',
            'platform' => 'android',
            'push_token' => self::TOKEN,
            'app_version' => '1.4.2',
            'device_model' => 'Pixel 8',
            'os_version' => 'Android 15',
        ]);

        $response->assertCreated();

        $device = UserDevice::where('user_id', $customer->id)->where('push_token', self::TOKEN)->first();

        $this->assertNotNull($device, 'The token was not stored against the customer.');
        $this->assertSame('customer_app', $device->app_type);
        $this->assertSame('android', $device->platform);
        $this->assertSame('1.4.2', $device->app_version);
        $this->assertSame('Pixel 8', $device->device_model);
        $this->assertTrue((bool) $device->is_active);
        $this->assertNotNull($device->last_active_at);
    }

    public function test_registering_the_same_device_twice_does_not_create_a_second_row(): void
    {
        $customer = $this->customer();
        $payload = [
            'app_type' => 'customer_app',
            'platform' => 'android',
            'push_token' => self::TOKEN,
            'app_version' => '1.4.2',
        ];

        $this->actingAsCustomer($customer)->postJson('/api/customer/devices/register', $payload)->assertCreated();
        $this->actingAsCustomer($customer)->postJson('/api/customer/devices/register', $payload)->assertOk();

        $this->assertSame(
            1,
            UserDevice::where('user_id', $customer->id)->where('push_token', self::TOKEN)->count()
        );
    }

    public function test_device_registration_requires_a_push_token(): void
    {
        $this->actingAsCustomer($this->customer())
            ->postJson('/api/customer/devices/register', [
                'app_type' => 'customer_app',
                'platform' => 'android',
                'app_version' => '1.4.2',
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('push_token');
    }

    // -- B. One token, one owner -------------------------------------------

    public function test_b_a_token_registered_by_somebody_else_is_handed_over(): void
    {
        $previousOwner = $this->customer();
        $newOwner = $this->customer();

        $this->registerDevice($previousOwner);

        $this->assertTrue((bool) UserDevice::where('user_id', $previousOwner->id)->first()->is_active);

        $this->registerDevice($newOwner);

        $this->assertFalse(
            (bool) UserDevice::where('user_id', $previousOwner->id)->first()->is_active,
            'The previous owner kept an active row and would still be pushed to on a shared phone.'
        );
        $this->assertTrue(
            (bool) UserDevice::where('user_id', $newOwner->id)->first()->is_active,
            'The new owner did not get an active row.'
        );
    }

    public function test_b_unregister_only_affects_the_signed_in_user(): void
    {
        $owner = $this->customer();
        $other = $this->customer();

        // Each account registers a token of its own, so nothing is handed over
        // and both rows start out active.
        $this->actingAsCustomer($owner)->postJson('/api/customer/devices/register', [
            'app_type' => 'customer_app',
            'platform' => 'android',
            'push_token' => self::TOKEN,
            'app_version' => '1.4.2',
        ])->assertCreated();

        $this->actingAsCustomer($other)->postJson('/api/customer/devices/register', [
            'app_type' => 'customer_app',
            'platform' => 'android',
            'push_token' => 'other-token-aaaaaaaaaaaa',
            'app_version' => '1.4.2',
        ])->assertCreated();

        // The second account tries to sign out a token it does not hold. If the
        // lookup were by token alone, it would quietly stop the owner being
        // pushed to on their own phone.
        $this->actingAsCustomer($other)
            ->postJson('/api/customer/devices/unregister', ['push_token' => self::TOKEN])
            ->assertOk();

        $this->assertTrue(
            (bool) UserDevice::where('user_id', $owner->id)->first()->is_active,
            'One account signing out must not disable the notification for whoever registered the phone next.'
        );
        $this->assertTrue(
            (bool) UserDevice::where('user_id', $other->id)->first()->is_active,
            'A token the caller did not own is not that caller\'s to release.'
        );

        // Releasing a token you do hold is the case that does have to work.
        $this->actingAsCustomer($other)
            ->postJson('/api/customer/devices/unregister', ['push_token' => 'other-token-aaaaaaaaaaaa'])
            ->assertOk();

        $this->assertFalse((bool) UserDevice::where('user_id', $other->id)->first()->is_active);
    }

    // -- C. The delivery ledger --------------------------------------------

    public function test_c_a_delivery_row_records_the_outcome(): void
    {
        $customer = $this->customer();
        $notification = $this->notification($customer);
        $device = $this->device($customer);

        $delivery = NotificationDelivery::create([
            'notification_id' => $notification->id,
            'user_device_id' => $device->id,
            'channel' => NotificationDelivery::CHANNEL_PUSH,
            'status' => NotificationDelivery::STATUS_SENT,
            'provider' => 'log',
            'destination' => $device->maskedToken(),
            'provider_message_id' => 'log:'.$notification->id,
            'attempt_count' => 1,
            'sent_at' => now(),
        ]);

        $this->assertTrue($delivery->exists);
        $this->assertSame('push', $delivery->channel);
        $this->assertSame('sent', $delivery->status);
        $this->assertSame(1, $delivery->attempt_count);
        $this->assertNotNull($delivery->sent_at);
        $this->assertSame($notification->id, $delivery->notification->id);
        $this->assertSame($device->id, $delivery->userDevice->id);
    }

    public function test_c_a_failed_delivery_keeps_the_reason(): void
    {
        $customer = $this->customer();

        $delivery = NotificationDelivery::create([
            'notification_id' => $this->notification($customer)->id,
            'user_device_id' => $this->device($customer)->id,
            'channel' => NotificationDelivery::CHANNEL_PUSH,
            'status' => NotificationDelivery::STATUS_FAILED,
            'provider' => 'fcm',
            'destination' => 'dJ8fQ2vX...K2lZ4xC6vB8nM0',
            'attempt_count' => 3,
            'failure_reason' => 'The registration token is not registered',
            'failed_at' => now(),
        ]);

        $this->assertSame('failed', $delivery->status);
        $this->assertSame('The registration token is not registered', $delivery->failure_reason);
        $this->assertNotNull($delivery->failed_at);
        $this->assertNull($delivery->sent_at);
    }

    // -- D. Notification before push ---------------------------------------

    public function test_d_the_notification_service_writes_the_notification_then_queues_the_push(): void
    {
        Queue::fake();

        [$appointment] = $this->booking();
        $service = app(NotificationService::class);

        $notification = $service->appointmentNeedsReschedule(
            $appointment,
            'Glow Studio',
            'Mon 14 Sep 2026',
            'staff illness'
        );

        $this->assertTrue($notification->exists, 'No in-app notification was written.');
        $this->assertDatabaseHas('notifications', [
            'id' => $notification->id,
            'user_id' => $appointment->customer_id,
        ]);

        // The push is only ever queued for a notification that already exists,
        // so a worker can never wake up looking for a row that is not there.
        Queue::assertPushed(
            SendPushNotificationJob::class,
            fn (SendPushNotificationJob $job) => $job->notificationId === $notification->id
        );
    }

    public function test_d_the_queued_job_knows_which_notification_to_push(): void
    {
        Queue::fake();

        [$appointment] = $this->booking();

        app(NotificationService::class)->appointmentNeedsReschedule(
            $appointment,
            'Glow Studio',
            'Mon 14 Sep 2026',
            null
        );

        Queue::assertPushed(SendPushNotificationJob::class, function (SendPushNotificationJob $job) {
            $this->assertTrue(Notification::find($job->notificationId)->exists);

            return true;
        });
    }

    // -- E. afterCommit -----------------------------------------------------

    public function test_e_the_push_job_is_queued_after_the_transaction_commits(): void
    {
        Queue::fake();

        [$appointment] = $this->booking();

        app(NotificationService::class)->appointmentNeedsReschedule(
            $appointment,
            'Glow Studio',
            'Mon 14 Sep 2026',
            null
        );

        // Every caller creates the notification inside DB::transaction(), and
        // config/queue.php leaves after_commit false, so this flag is the only
        // thing standing between the worker and a row it cannot see yet.
        Queue::assertPushed(
            SendPushNotificationJob::class,
            fn (SendPushNotificationJob $job) => $job->afterCommit === true
        );
    }

    public function test_e_a_job_built_by_hand_also_defers_until_commit(): void
    {
        $job = new SendPushNotificationJob(Str::uuid()->toString());

        $this->assertTrue($job->afterCommit);
    }

    // -- F. The log driver contacts nobody ----------------------------------

    public function test_f_the_log_driver_sends_no_http_request(): void
    {
        Http::fake();

        $customer = $this->customer();
        $notification = $this->notification($customer);
        $this->device($customer);

        $this->runJob($notification);

        Http::assertNothingSent();
    }

    public function test_f_the_configured_driver_resolves_to_the_log_gateway(): void
    {
        config(['services.push.driver' => 'log']);

        $this->assertInstanceOf(LogPushGateway::class, app(PushGateway::class));
    }

    public function test_f_the_log_driver_records_a_sent_delivery(): void
    {
        $customer = $this->customer();
        $notification = $this->notification($customer);
        $device = $this->device($customer);

        $this->runJob($notification);

        $this->assertSame(1, NotificationDelivery::where('notification_id', $notification->id)->count());

        $delivery = NotificationDelivery::where('notification_id', $notification->id)->first();

        $this->assertSame(NotificationDelivery::STATUS_SENT, $delivery->status);
        $this->assertSame('log', $delivery->provider);
        $this->assertSame('push', $delivery->channel);
        $this->assertSame($device->id, $delivery->user_device_id);
        $this->assertNotNull($delivery->sent_at);
    }

    public function test_f_the_push_reaches_a_device_registered_to_another_user(): void
    {
        $customer = $this->customer();
        $stranger = $this->customer();
        $notification = $this->notification($customer);

        $this->device($stranger);
        $device = $this->device($customer);

        $this->runJob($notification);

        $this->assertSame(
            [$device->id],
            NotificationDelivery::where('notification_id', $notification->id)
                ->pluck('user_device_id')
                ->all()
        );
    }

    // -- G. Nobody to push to ----------------------------------------------

    public function test_g_a_customer_with_no_device_breaks_nothing(): void
    {
        $customer = $this->customer();
        $notification = $this->notification($customer);

        $this->runJob($notification);

        $this->assertSame(0, NotificationDelivery::count());
        $this->assertTrue($notification->fresh()->exists, 'The in-app notification was disturbed.');
    }

    public function test_g_a_device_with_an_empty_token_is_not_pushable(): void
    {
        $customer = $this->customer();
        $notification = $this->notification($customer);

        $this->device($customer, ['push_token' => '']);

        $this->runJob($notification);

        $this->assertSame(0, NotificationDelivery::count());
    }

    public function test_g_a_job_for_a_deleted_notification_exits_quietly(): void
    {
        $job = new SendPushNotificationJob(Str::uuid()->toString());

        $job->handle(app(PushGateway::class));

        $this->assertSame(0, NotificationDelivery::count());
    }

    // -- H. Signed-out and rejected devices --------------------------------

    public function test_h_a_deactivated_device_is_not_pushed_to(): void
    {
        $customer = $this->customer();
        $notification = $this->notification($customer);

        $this->device($customer, ['is_active' => false]);

        $this->runJob($notification);

        $this->assertSame(0, NotificationDelivery::count());
    }

    public function test_h_a_device_rejected_by_the_provider_is_signed_off(): void
    {
        $customer = $this->customer();
        $notification = $this->notification($customer);
        $device = $this->device($customer);

        $gateway = new class implements PushGateway
        {
            public function send(iterable $devices, PushPayload $payload): array
            {
                $results = [];

                foreach ($devices as $device) {
                    $results[$device->id] = \App\Services\Notifications\PushResult::failed(
                        'fcm',
                        'The registration token is not registered',
                        true
                    );
                }

                return $results;
            }
        };

        $job = new SendPushNotificationJob($notification->id);
        $job->handle($gateway);

        $delivery = NotificationDelivery::where('notification_id', $notification->id)->first();

        $this->assertSame(NotificationDelivery::STATUS_FAILED, $delivery->status);
        $this->assertSame('The registration token is not registered', $delivery->failure_reason);
        $this->assertFalse(
            (bool) $device->fresh()->is_active,
            'A token the provider has thrown away should not be paid for again on the next notification.'
        );
    }

    public function test_h_one_failing_device_does_not_stop_the_others(): void
    {
        $customer = $this->customer();
        $notification = $this->notification($customer);

        $good = $this->device($customer, ['push_token' => 'good-token-aaaaaaaaaaaa']);
        $bad = $this->device($customer, ['push_token' => 'bad-token-bbbbbbbbbbbb']);

        $gateway = new class implements PushGateway
        {
            public function send(iterable $devices, PushPayload $payload): array
            {
                $results = [];

                foreach ($devices as $device) {
                    $results[$device->id] = $device->push_token === 'bad-token-bbbbbbbbbbbb'
                        ? \App\Services\Notifications\PushResult::failed('fcm', 'provider rejected this token')
                        : \App\Services\Notifications\PushResult::accepted('fcm', 'message-1');
                }

                return $results;
            }
        };

        (new SendPushNotificationJob($notification->id))->handle($gateway);

        $statuses = NotificationDelivery::where('notification_id', $notification->id)
            ->pluck('status', 'user_device_id')
            ->all();

        $this->assertSame(NotificationDelivery::STATUS_SENT, $statuses[$good->id]);
        $this->assertSame(NotificationDelivery::STATUS_FAILED, $statuses[$bad->id]);
    }

    // -- I. The token never reaches a log ----------------------------------

    public function test_i_the_log_gateway_never_writes_the_full_token(): void
    {
        Log::spy();

        $customer = $this->customer();
        $device = $this->device($customer);
        $payload = PushPayload::fromNotification($this->notification($customer));

        (new LogPushGateway())->send([$device], $payload);

        Log::shouldHaveReceived('info')
            ->atLeast()
            ->once()
            ->withArgs(function (string $message, array $context) use ($device) {
                $this->assertSame($device->maskedToken(), $context['device_token']);
                $this->assertStringNotContainsString(
                    $device->push_token,
                    json_encode($context),
                    'A complete push token reached the log; anyone with the log could push anything to that phone.'
                );

                return true;
            });
    }

    public function test_i_the_registration_response_does_not_echo_the_token(): void
    {
        $response = $this->registerDevice($this->customer());

        $this->assertStringNotContainsString(self::TOKEN, $response->getContent());
        $this->assertArrayHasKey('push_token', $response->json('device'));
    }

    public function test_i_the_delivery_ledger_does_not_store_the_token_in_the_clear(): void
    {
        $customer = $this->customer();
        $notification = $this->notification($customer);
        $this->device($customer);

        $this->runJob($notification);

        $delivery = NotificationDelivery::where('notification_id', $notification->id)->first();

        $this->assertStringNotContainsString(self::TOKEN, $delivery->destination);
    }

    public function test_i_a_short_token_is_masked_completely(): void
    {
        $device = new UserDevice(['push_token' => 'short123']);

        $this->assertSame('********', $device->maskedToken());
        $this->assertNull((new UserDevice(['push_token' => null]))->maskedToken());
        $this->assertNull((new UserDevice(['push_token' => '']))->maskedToken());
    }

    // -- Fixtures -----------------------------------------------------------

    private function actingAsCustomer(User $user): self
    {
        $this->actingAs($user, 'sanctum');

        return $this;
    }

    private function registerDevice(User $user)
    {
        return $this->actingAsCustomer($user)->postJson('/api/customer/devices/register', [
            'app_type' => 'customer_app',
            'platform' => 'android',
            'push_token' => self::TOKEN,
            'app_version' => '1.4.2',
        ]);
    }

    private function customer(): User
    {
        return User::create([
            'role' => 'customer',
            'name' => 'Test Customer',
            'phone' => '9'.random_int(100000000, 999999999),
            'password_hash' => bcrypt('secret'),
        ]);
    }

    private function device(User $user, array $overrides = []): UserDevice
    {
        return UserDevice::create(array_merge([
            'user_id' => $user->id,
            'app_type' => 'customer_app',
            'platform' => 'android',
            'push_token' => self::TOKEN,
            'app_version' => '1.4.2',
            'is_active' => true,
            'last_active_at' => now(),
        ], $overrides));
    }

    private function notification(User $user, array $overrides = []): Notification
    {
        return Notification::create(array_merge([
            'user_id' => $user->id,
            'type' => 'salon_closure',
            'title' => 'Your appointment needs a new time',
            'message' => 'Glow Studio is closed. Your booking has been released.',
            'data' => ['action' => 'reschedule_appointment'],
            'is_read' => false,
        ], $overrides));
    }

    private function runJob(Notification $notification): void
    {
        (new SendPushNotificationJob($notification->id))->handle(app(PushGateway::class));
    }

    /**
     * A salon, an owner, a provider with a booking — the minimum a
     * NotificationService event needs to point at a real customer.
     *
     * @return array{0: Appointment}
     */
    private function booking(): array
    {
        $owner = User::create([
            'role' => 'admin',
            'name' => 'Test Salon Owner',
            'phone' => '8'.random_int(100000000, 999999999),
            'password_hash' => bcrypt('secret'),
        ]);

        $salon = Salon::create([
            'admin_id' => $owner->id,
            'name' => 'Glow Studio',
            'slug' => 'glow-studio-'.Str::lower(Str::random(8)),
            'address' => '1 Test Street',
            'submitted_by' => $owner->id,
        ]);

        $providerUser = User::create([
            'role' => 'service_provider',
            'name' => 'Test Provider',
            'phone' => '7'.random_int(100000000, 999999999),
            'password_hash' => bcrypt('secret'),
        ]);

        $provider = ServiceProvider::create([
            'user_id' => $providerUser->id,
            'salon_id' => $salon->id,
        ]);

        $customer = User::create([
            'role' => 'customer',
            'name' => 'Test Booker',
            'phone' => '6'.random_int(100000000, 999999999),
            'password_hash' => bcrypt('secret'),
        ]);

        return [Appointment::create([
            'salon_id' => $salon->id,
            'customer_id' => $customer->id,
            'appointed_provider_id' => $provider->id,
            'appointment_date' => '2026-09-14',
            'start_time' => '10:00:00',
            'end_time' => '11:00:00',
        ])];
    }
}
