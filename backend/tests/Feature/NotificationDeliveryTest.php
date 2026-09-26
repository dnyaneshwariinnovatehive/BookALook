<?php

namespace Tests\Feature;

use App\Jobs\RetryPendingPushDeliveryJob;
use App\Jobs\SendPushNotificationJob;
use App\Models\Appointment;
use App\Models\Notification;
use App\Models\NotificationDelivery;
use App\Models\NotificationPreference;
use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Models\User;
use App\Models\UserDevice;
use App\Services\Notifications\FcmAccessTokenProvider;
use App\Services\Notifications\FcmCredentials;
use App\Services\Notifications\FcmPushGateway;
use App\Services\Notifications\LogPushGateway;
use App\Services\Notifications\MissingFcmCredentials;
use App\Services\Notifications\NotificationService;
use App\Services\Notifications\PushGateway;
use App\Services\Notifications\PushPayload;
use App\Services\Notifications\PushResult;
use App\Support\Notifications\NotificationType;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Str;
use RuntimeException;
use Tests\TestCase;

/**
 * An FCM access token provider that hands back a token without asking Google.
 *
 * A test seam and nothing more. The JWT signing and the token exchange are
 * FcmAccessTokenProvider's own concern and are tested against Google's endpoint
 * in FcmAccessTokenProviderTest; here they would only stand between the test and
 * the behaviour being examined.
 */
class StubbedFcmAccessTokenProvider extends FcmAccessTokenProvider
{
    public function token(): string
    {
        return 'stubbed-access-token';
    }
}

/**
 * Everything added after the pipeline first worked: device ownership, the
 * preference switches, the FCM adapter itself, retrying a delivery that a
 * provider would not take, and the business events that now call the service.
 *
 * Separated from PushNotificationFoundationTest rather than appended to it,
 * because that file is the record of one decision — that the pipeline works
 * with a fake provider — and this is a different claim: that the parts around
 * it behave. A failure in here should not send anyone looking at the queue.
 */
class NotificationDeliveryTest extends TestCase
{
    use DatabaseTransactions;

    private const TOKEN = 'cR7tY2uI9oP3aS6dF1gH4jK8lZ5xC2vB7nM0qW4eR6tY1uI:APA91bH3xK2mQ9wR4tY6uI3oP1aS5dF0gH8jK2lZ4xC6vB8nM0';

    private const OTHER_TOKEN = 'zX9wV2uT5yP7aB4dF1gH6jK0lZ3xC8vN5nM2qW7eR3tY6uI:APA91bH8xK4mQ2wR6tY9uI5oP3aS7dF2gH1jK5lZ8xC3vB7nM1';

    // -- A. Device ownership ------------------------------------------------

    public function test_a_token_registered_by_one_user_is_taken_over_by_the_next(): void
    {
        $first = $this->customer();
        $second = $this->customer();

        $this->registerDevice($first, ['push_token' => self::TOKEN]);
        $this->registerDevice($second, ['push_token' => self::TOKEN]);

        // Two rows, because the same handset under two accounts is a real thing
        // — a shared family phone, or a customer account created for a number
        // that already had the app. One row means the second registration
        // silently re-pointed the first user's device at somebody else.
        $this->assertSame(2, UserDevice::where('push_token', self::TOKEN)->count());

        // And only the newest owner is live: the old one must stop receiving the
        // first user's notifications the moment the phone changes hands.
        $this->assertFalse((bool) UserDevice::where('user_id', $first->id)->where('push_token', self::TOKEN)->value('is_active'));
        $this->assertTrue((bool) UserDevice::where('user_id', $second->id)->where('push_token', self::TOKEN)->value('is_active'));
    }

    public function test_registering_the_same_token_twice_updates_rather_than_duplicates(): void
    {
        $user = $this->customer();

        $first = $this->registerDevice($user, ['push_token' => self::TOKEN, 'app_version' => '1.4.2']);
        $second = $this->registerDevice($user, ['push_token' => self::TOKEN, 'app_version' => '1.5.0']);

        $first->assertCreated();
        $second->assertOk();

        $this->assertSame(1, UserDevice::where('user_id', $user->id)->where('push_token', self::TOKEN)->count());
        $this->assertSame('1.5.0', UserDevice::where('user_id', $user->id)->where('push_token', self::TOKEN)->value('app_version'));
    }

    public function test_a_partner_registers_a_device_through_the_partner_api(): void
    {
        $partner = $this->user('service_provider');

        $this->actingAs($partner, 'sanctum')
            ->postJson('/api/partner/devices/register', [
                'app_type' => 'partner_app',
                'platform' => 'android',
                'push_token' => self::TOKEN,
                'app_version' => '1.0.0',
            ])
            ->assertCreated();

        $device = UserDevice::where('user_id', $partner->id)->first();

        $this->assertNotNull($device);
        $this->assertSame('partner_app', $device->app_type);
    }

    public function test_a_device_needs_a_token_to_be_worth_registering(): void
    {
        $this->actingAs($this->customer(), 'sanctum')
            ->postJson('/api/customer/devices/register', [
                'app_type' => 'customer_app',
                'platform' => 'android',
                // A device row with no token is a row that can never receive
                // anything, and reads in a debug panel like a working device.
                'push_token' => '',
                'app_version' => '1.4.2',
            ])
            ->assertJsonValidationErrors('push_token');
    }

    public function test_one_user_cannot_release_another_users_device(): void
    {
        $owner = $this->customer();
        $stranger = $this->customer();

        $this->registerDevice($owner, ['push_token' => self::TOKEN]);

        $this->actingAs($stranger, 'sanctum')
            ->postJson('/api/customer/devices/unregister', ['push_token' => self::TOKEN])
            ->assertOk()
            ->assertJsonPath('message', 'That device was not registered for push notifications.');

        $this->assertTrue((bool) UserDevice::where('user_id', $owner->id)->where('push_token', self::TOKEN)->value('is_active'));
    }

    public function test_a_device_list_shows_masked_tokens_only(): void
    {
        $user = $this->customer();
        $this->registerDevice($user, ['push_token' => self::TOKEN]);

        $response = $this->actingAs($user, 'sanctum')->getJson('/api/customer/devices')->assertOk();

        $body = $response->json('devices.0');

        $this->assertNotSame(self::TOKEN, $body['push_token']);
        $this->assertStringNotContainsString(self::TOKEN, $response->getContent());
        $this->assertTrue($body['is_active']);
    }

    public function test_activity_does_not_resurrect_a_device_the_provider_rejected(): void
    {
        $user = $this->customer();
        $this->registerDevice($user, ['push_token' => self::TOKEN]);

        // Simulate the push job having signed it off after FCM said the token
        // was no longer valid.
        UserDevice::where('user_id', $user->id)->update(['is_active' => false, 'last_active_at' => now()->subDays(3)]);

        $this->actingAs($user, 'sanctum')
            ->postJson('/api/customer/devices/activity', ['push_token' => self::TOKEN])
            ->assertOk();

        // If "I am still here" reactivated it, the next notification would pay
        // to ask FCM about a token FCM has already said is dead, forever.
        $this->assertFalse((bool) UserDevice::where('user_id', $user->id)->value('is_active'));
    }

    // -- B. Preferences -----------------------------------------------------

    public function test_a_user_who_has_never_set_anything_gets_everything_on(): void
    {
        $user = $this->customer();

        $response = $this->actingAs($user, 'sanctum')->getJson('/api/customer/notifications/preferences')->assertOk();

        // A preference table that defaults to silence would make a fresh install
        // quietly drop every push, which is the kind of bug nobody reports.
        $this->assertTrue($response->json('preferences.push_enabled'));
        $this->assertTrue($response->json('preferences.promotional_notifications'));
        $this->assertSame('customer_app', $response->json('preferences.app_type'));
    }

    public function test_a_switch_is_saved_and_read_back(): void
    {
        $user = $this->customer();

        $this->actingAs($user, 'sanctum')
            ->putJson('/api/customer/notifications/preferences', ['push_enabled' => false])
            ->assertOk()
            ->assertJsonPath('preferences.push_enabled', false);

        $this->assertTrue(
            $this->actingAs($user, 'sanctum')
                ->getJson('/api/customer/notifications/preferences')
                ->json('preferences.promotional_notifications'),
            'A partial update must not reset the switches it did not mention.',
        );
    }

    public function test_turning_push_off_stops_the_push_but_not_the_inbox_row(): void
    {
        $user = $this->customer();
        $this->registerDevice($user, ['push_token' => self::TOKEN]);

        NotificationPreference::create([
            'user_id' => $user->id,
            'app_type' => 'customer_app',
            'push_enabled' => false,
        ]);

        $notification = $this->notification($user, ['type' => NotificationType::BOOKING_CONFIRMED]);

        Queue::fake();
        (new SendPushNotificationJob($notification->id))->handle(app(PushGateway::class));

        // The row in the inbox is the record of what happened and is never
        // withdrawn; the push is the mirror, and only the mirror is suppressed.
        $this->assertDatabaseHas('notifications', ['id' => $notification->id]);
        $this->assertDatabaseMissing('notification_deliveries', ['notification_id' => $notification->id]);
    }

    public function test_the_promotional_switch_is_wired_but_no_event_claims_it_yet(): void
    {
        $user = $this->customer();
        $preference = NotificationPreference::forUser($user->id, 'customer_app');

        // Every type in the vocabulary today is something an account depends on.
        // That is the honest state of the system, and asserting it is more
        // useful than inventing a promotional type in a test: when marketing
        // notifications are added, this test is the one that has to change, and
        // whoever adds them will see exactly why.
        $promotional = array_filter(
            NotificationType::all(),
            fn (string $type) => NotificationType::isPromotional($type),
        );

        $this->assertSame([], array_values($promotional));

        // So switching marketing off changes nothing today — and must not
        // silence a transaction the customer needs.
        $preference->promotional_notifications = false;

        foreach (NotificationType::all() as $type) {
            $this->assertTrue(
                $preference->allows($type),
                "Turning marketing off silenced {$type}, which is not marketing.",
            );
        }
    }

    public function test_the_master_switch_silences_everything_including_transactions(): void
    {
        $user = $this->customer();

        $preference = NotificationPreference::forUser($user->id, 'customer_app');
        $preference->push_enabled = false;

        $this->assertFalse($preference->allows(NotificationType::BOOKING_CONFIRMED));
        $this->assertFalse($preference->allows(NotificationType::APPOINTMENT_REMINDER));
    }

    public function test_each_app_gets_its_own_preferences(): void
    {
        $user = $this->user('service_provider');

        $this->actingAs($user, 'sanctum')
            ->putJson('/api/partner/notifications/preferences', ['push_enabled' => false])
            ->assertOk();

        $this->assertFalse(
            NotificationPreference::forUser($user->id, 'partner_app')->push_enabled,
        );

        // The same person, the same account, a different app: the row is keyed
        // on both, and a partner app must never inherit the customer app's
        // answer to a question it never asked.
        $this->assertTrue(
            NotificationPreference::forUser($user->id, 'customer_app')->push_enabled,
        );
    }

    // -- C. The FCM adapter -------------------------------------------------

    public function test_the_fcm_driver_refuses_to_run_unconfigured_instead_of_faking_success(): void
    {
        config([
            'services.push.driver' => 'fcm',
            'services.push.fcm.project_id' => null,
            'services.push.fcm.client_email' => null,
            'services.push.fcm.private_key' => null,
            'services.push.fcm.credentials_path' => null,
        ]);

        // The payment and WhatsApp drivers degrade to a log driver so a
        // half-configured environment cannot break a booking. A push driver that
        // did the same would report every delivery as `sent` and make a broken
        // server look like a working one — so this one refuses, by name.
        $this->expectException(MissingFcmCredentials::class);
        $this->expectExceptionMessageMatches('/FCM_PROJECT_ID/');

        app(PushGateway::class);
    }

    public function test_the_log_driver_is_still_what_an_unconfigured_environment_gets(): void
    {
        config(['services.push.driver' => 'log']);

        $this->assertInstanceOf(LogPushGateway::class, app(PushGateway::class));
    }

    public function test_credentials_can_come_from_a_service_account_file_alone(): void
    {
        $path = tempnam(sys_get_temp_dir(), 'fcm').'.json';
        file_put_contents($path, json_encode([
            'type' => 'service_account',
            'project_id' => 'bookalook-test',
            'client_email' => 'test@bookalook-test.iam.gserviceaccount.com',
            // Literal \n, exactly as it arrives inside a real downloaded file.
            'private_key' => "-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----\\n",
        ]));

        try {
            config([
                'services.push.fcm.project_id' => null,
                'services.push.fcm.client_email' => null,
                'services.push.fcm.private_key' => null,
                'services.push.fcm.credentials_path' => $path,
            ]);

            $credentials = FcmCredentials::fromConfig();

            $this->assertSame('bookalook-test', $credentials->projectId);
            $this->assertSame('test@bookalook-test.iam.gserviceaccount.com', $credentials->clientEmail);
            $this->assertStringContainsString("\n", $credentials->privateKey);
            $this->assertStringNotContainsString('\n', $credentials->privateKey);
        } finally {
            @unlink($path);
        }
    }

    public function test_an_unreadable_credentials_path_names_the_file_not_its_contents(): void
    {
        config([
            'services.push.fcm.project_id' => 'p',
            'services.push.fcm.client_email' => 'e',
            'services.push.fcm.private_key' => null,
            'services.push.fcm.credentials_path' => '/nope/not/here.json',
        ]);

        $this->expectException(MissingFcmCredentials::class);
        $this->expectExceptionMessageMatches('/cannot read/');

        FcmCredentials::fromConfig();
    }

    public function test_fcm_marks_a_dead_token_as_a_permanent_failure_and_signs_the_device_off(): void
    {
        $user = $this->customer();
        $device = $this->device($user);
        $notification = $this->notification($user);

        Http::fake([
            'fcm.googleapis.com/*' => Http::response([
                'error' => [
                    'status' => 'NOT_FOUND',
                    'message' => 'Requested entity was not found.',
                ],
            ], 404),
        ]);

        $result = $this->gateway()->send([$device], PushPayload::fromNotification($notification))[$device->id];

        $this->assertFalse($result->accepted);
        $this->assertTrue($result->deactivateDevice, 'A token FCM has forgotten must be stopped being used.');
        $this->assertFalse($result->retryable, 'Asking again cannot make FCM remember a token.');
    }

    public function test_fcm_leaves_a_rate_limited_push_retryable_and_the_device_alive(): void
    {
        $user = $this->customer();
        $device = $this->device($user);
        $notification = $this->notification($user);

        Http::fake(['fcm.googleapis.com/*' => Http::response(['error' => ['message' => 'Too many requests.']], 429)]);

        $result = $this->gateway()->send([$device], PushPayload::fromNotification($notification))[$device->id];

        $this->assertFalse($result->accepted);
        $this->assertTrue($result->retryable, 'A rate limit is about us being busy, not about the phone.');
        $this->assertFalse($result->deactivateDevice, 'The token is fine; only our timing was wrong.');
    }

    public function test_a_bad_request_does_not_sign_off_a_working_phone(): void
    {
        $user = $this->customer();
        $device = $this->device($user);
        $notification = $this->notification($user);

        // A 400 that is about the message, not the token — an over-long title, a
        // bad field. Treating every 400 as a dead token would quietly retire
        // working phones over our own malformed payloads.
        Http::fake(['fcm.googleapis.com/*' => Http::response(['error' => ['message' => 'Invalid value at message.notification.title']], 400)]);

        $result = $this->gateway()->send([$device], PushPayload::fromNotification($notification))[$device->id];

        $this->assertFalse($result->accepted);
        $this->assertFalse($result->deactivateDevice);
        $this->assertFalse($result->retryable);
    }

    public function test_a_revoked_service_account_fails_loudly_rather_than_being_retried_per_device(): void
    {
        $user = $this->customer();
        $device = $this->device($user);
        $notification = $this->notification($user);

        Http::fake(['fcm.googleapis.com/*' => Http::response(['error' => ['message' => 'Credential revoked.']], 401)]);

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessageMatches('/rejected our access token/');

        $this->gateway()->send([$device], PushPayload::fromNotification($notification));
    }

    public function test_a_provider_reason_is_stored_without_the_token_it_quoted(): void
    {
        $user = $this->customer();
        $device = $this->device($user);
        $notification = $this->notification($user);

        // FCM quotes the offending token back in some malformed-token
        // complaints, and that string ends up in the delivery ledger and the
        // log. Long unbroken strings are replaced before either.
        Http::fake([
            'fcm.googleapis.com/*' => Http::response([
                'error' => ['message' => 'Invalid registration token '.self::TOKEN.' supplied.'],
            ], 400),
        ]);

        $result = $this->gateway()->send([$device], PushPayload::fromNotification($notification))[$device->id];

        $this->assertStringNotContainsString(self::TOKEN, (string) $result->failureReason);
        $this->assertStringContainsString('[redacted-token]', (string) $result->failureReason);
    }

    public function test_an_oversize_message_is_refused_before_it_costs_one_request_per_phone(): void
    {
        $user = $this->customer();
        $device = $this->device($user);

        // FCM rejects anything over 4KB with a 400 for every device, which is
        // both wrong (nothing is wrong with the phones) and expensive.
        $notification = $this->notification($user, [
            'message' => str_repeat('A very long notification body. ', 300),
        ]);

        Http::fake();
        $gateway = $this->gateway();

        try {
            $gateway->send([$device], PushPayload::fromNotification($notification));
            $this->fail('An oversize message should not be sent at all.');
        } catch (RuntimeException $e) {
            $this->assertStringContainsString('over FCM', $e->getMessage());
        }

        Http::assertNothingSent();
    }

    public function test_the_push_actually_carries_the_title_the_customer_will_read(): void
    {
        $user = $this->customer();
        $device = $this->device($user);
        $notification = $this->notification($user, [
            'title' => 'Booking confirmed',
            'message' => 'Your booking at Glow Studio is confirmed.',
        ]);

        Http::fake(['fcm.googleapis.com/*' => Http::response(['name' => 'projects/x/messages/0:1'])]);
        $this->gateway()->send([$device], PushPayload::fromNotification($notification));

        Http::assertSent(function ($request) {
            $message = $request->data()['message'];

            return $message['notification']['title'] === 'Booking confirmed'
                && $message['notification']['body'] === 'Your booking at Glow Studio is confirmed.'
                // Both blocks are sent on purpose: notification is the banner,
                // data is what the app reads to decide where a tap goes.
                && $message['data']['type'] === NotificationType::BOOKING_CONFIRMED
                && $message['android']['notification']['channel_id'] === 'bookalook_notifications';
        });
    }

    public function test_the_action_and_its_entity_travel_in_the_data_block(): void
    {
        $user = $this->customer();
        $appointment = $this->booking($user);

        $payload = PushPayload::fromNotification($this->notification($user, [
            'type' => NotificationType::BOOKING_CONFIRMED,
            'data' => ['action' => 'view_appointment', 'appointment_id' => $appointment->id],
        ]));

        $data = $payload->toDataArray();

        $this->assertSame('view_appointment', $data['action']);
        $this->assertSame('appointment', $data['entity_type']);
        $this->assertSame($appointment->id, $data['entity_id']);

        // Every value a string, because that is FCM's own rule: a nested array
        // is the quiet way to have a notification arrive with no payload.
        foreach ($data as $value) {
            $this->assertIsString($value);
        }
    }

    public function test_a_payload_cannot_impersonate_another_notification(): void
    {
        $user = $this->customer();
        $notification = $this->notification($user);

        $data = PushPayload::fromNotification($notification)->toDataArray();

        $this->assertSame($notification->id, $data['notification_id']);
    }

    // -- D. Retrying what the provider would not take -----------------------

    public function test_a_pending_delivery_is_retried_rather_than_left_in_the_letterbox(): void
    {
        $user = $this->customer();
        $device = $this->device($user);
        $notification = $this->notification($user);

        Queue::fake();

        (new SendPushNotificationJob($notification->id))->handle(
            $this->fakeGateway([$device->id => PushResult::failed('test', 'Too many requests.', retryable: true)])
        );

        $delivery = NotificationDelivery::where('notification_id', $notification->id)->first();

        $this->assertNotNull($delivery);
        $this->assertSame(NotificationDelivery::STATUS_PENDING, $delivery->status);

        // A `pending` row is a promise that somebody will come back to it. Without
        // this the row sits there forever and the retries flag on PushResult is
        // a lie: a rate-limited push reported as retried when nobody retried it.
        Queue::assertPushed(RetryPendingPushDeliveryJob::class, fn (RetryPendingPushDeliveryJob $job) => $job->deliveryId === $delivery->id);
    }

    public function test_a_retry_settles_the_row_and_accumulates_the_attempt_count(): void
    {
        // QUEUE_CONNECTION is `sync` under test, so a dispatched retry would run
        // inline against the container's real gateway and settle the row before
        // this test could inspect it. Faking the queue makes the dispatch
        // observable and leaves the retry to be driven deliberately below.
        Queue::fake();
        $user = $this->customer();
        $device = $this->device($user);
        $notification = $this->notification($user);

        (new SendPushNotificationJob($notification->id))->handle(
            $this->fakeGateway([$device->id => PushResult::failed('test', 'Too many requests.', retryable: true)])
        );

        $delivery = NotificationDelivery::where('notification_id', $notification->id)->first();

        $this->assertSame(NotificationDelivery::STATUS_PENDING, $delivery->status);
        $this->assertSame(1, (int) $delivery->attempt_count);

        // The second try works.
        $retry = $this->fakeGateway([$device->id => PushResult::accepted('test', 'msg-2')]);
        (new RetryPendingPushDeliveryJob($delivery->id))->handle($retry);

        $delivery->refresh();

        $this->assertSame(NotificationDelivery::STATUS_SENT, $delivery->status);
        $this->assertSame('msg-2', $delivery->provider_message_id);
        $this->assertNotNull($delivery->sent_at);
        $this->assertNull($delivery->failure_reason);
        // Two tries, and the ledger says two. A retry that reset the count to 1
        // would make a repeated failure look like a first one.
        $this->assertSame(2, (int) $delivery->attempt_count);
    }

    public function test_a_retry_does_not_resend_to_the_phone_that_already_worked(): void
    {
        // QUEUE_CONNECTION is `sync` under test, so a dispatched retry would run
        // inline against the container's real gateway and settle the row before
        // this test could inspect it. Faking the queue makes the dispatch
        // observable and leaves the retry to be driven deliberately below.
        Queue::fake();
        $user = $this->customer();
        $notification = $this->notification($user);

        $good = $this->device($user, ['push_token' => self::TOKEN]);
        $bad = $this->device($user, ['push_token' => self::OTHER_TOKEN]);

        (new SendPushNotificationJob($notification->id))->handle($this->fakeGateway([
            $good->id => PushResult::accepted('test', 'msg-good'),
            $bad->id => PushResult::failed('test', 'Too many requests.', retryable: true),
        ]));

        $pending = NotificationDelivery::where('notification_id', $notification->id)
            ->where('user_device_id', $bad->id)
            ->first();

        $this->assertNotNull($pending);
        $this->assertSame(NotificationDelivery::STATUS_PENDING, $pending->status);

        // Only the row that was still pending is retried. Retrying the whole
        // notification would put a second copy on the phone that already worked.
        $retry = $this->fakeGateway([$bad->id => PushResult::accepted('test', 'msg-late')]);
        (new RetryPendingPushDeliveryJob($pending->id))->handle($retry);

        $this->assertSame([$bad->id], $retry->sentTo);

        // And no extra rows: one notification, one row per device, still.
        $this->assertSame(2, NotificationDelivery::where('notification_id', $notification->id)->count());
        $this->assertSame(1, (int) NotificationDelivery::where('user_device_id', $good->id)->value('attempt_count'));
    }

    public function test_a_retry_stops_at_the_device_the_user_has_left_behind(): void
    {
        // QUEUE_CONNECTION is `sync` under test, so a dispatched retry would run
        // inline against the container's real gateway and settle the row before
        // this test could inspect it. Faking the queue makes the dispatch
        // observable and leaves the retry to be driven deliberately below.
        Queue::fake();
        $user = $this->customer();
        $device = $this->device($user);
        $notification = $this->notification($user);

        (new SendPushNotificationJob($notification->id))->handle(
            $this->fakeGateway([$device->id => PushResult::failed('test', 'Too many requests.', retryable: true)])
        );

        $delivery = NotificationDelivery::where('notification_id', $notification->id)->first();

        // The user uninstalls, or signs out, between the two attempts.
        $device->update(['is_active' => false]);

        $retry = $this->fakeGateway([$device->id => PushResult::accepted('test', 'should-not-happen')]);
        (new RetryPendingPushDeliveryJob($delivery->id))->handle($retry);

        $this->assertSame([], $retry->sentTo, 'Nothing may be sent to a device that is no longer active.');
        $this->assertSame(NotificationDelivery::STATUS_FAILED, $delivery->fresh()->status);
    }

    public function test_a_retry_for_a_row_somebody_else_already_settled_does_nothing(): void
    {
        // QUEUE_CONNECTION is `sync` under test, so a dispatched retry would run
        // inline against the container's real gateway and settle the row before
        // this test could inspect it. Faking the queue makes the dispatch
        // observable and leaves the retry to be driven deliberately below.
        Queue::fake();
        $user = $this->customer();
        $device = $this->device($user);
        $notification = $this->notification($user);

        (new SendPushNotificationJob($notification->id))->handle(
            $this->fakeGateway([$device->id => PushResult::failed('test', 'Too many requests.', retryable: true)])
        );

        $delivery = NotificationDelivery::where('notification_id', $notification->id)->first();
        $delivery->update(['status' => NotificationDelivery::STATUS_SENT]);

        $retry = $this->fakeGateway([$device->id => PushResult::accepted('test', 'should-not-happen')]);
        (new RetryPendingPushDeliveryJob($delivery->id))->handle($retry);

        $this->assertSame([], $retry->sentTo, 'A delivery somebody else already settled must not be sent again.');
    }

    public function test_a_retry_that_keeps_failing_eventually_gives_up_and_records_why(): void
    {
        // QUEUE_CONNECTION is `sync` under test, so a dispatched retry would run
        // inline against the container's real gateway and settle the row before
        // this test could inspect it. Faking the queue makes the dispatch
        // observable and leaves the retry to be driven deliberately below.
        Queue::fake();
        $user = $this->customer();
        $device = $this->device($user);
        $notification = $this->notification($user);

        (new SendPushNotificationJob($notification->id))->handle(
            $this->fakeGateway([$device->id => PushResult::failed('test', 'Too many requests.', retryable: true)])
        );

        $delivery = NotificationDelivery::where('notification_id', $notification->id)->first();

        // The last permitted attempt. A provider that is down stays down, and a
        // job that retries forever is a queue that never drains.
        (new RetryPendingPushDeliveryJob($delivery->id, attempt: 3))->handle(
            $this->fakeGateway([$device->id => PushResult::failed('test', 'Still too many requests.', retryable: true)])
        );

        $delivery->refresh();

        $this->assertSame(NotificationDelivery::STATUS_FAILED, $delivery->status);
        $this->assertSame('Still too many requests.', $delivery->failure_reason);
    }

    // -- E. Business events -------------------------------------------------

    public function test_a_confirmed_booking_reaches_the_customer_and_the_salon(): void
    {
        [$appointment, $owner, $providerUser] = $this->bookingWithSalon();
        $service = app(NotificationService::class);

        $service->bookingConfirmed($appointment, 'Glow Studio', 'Sep 14, 2026 at 10:00 AM');
        $service->notifySalonOfNewBooking($appointment, 'Glow Studio', 'Sep 14, 2026 at 10:00 AM');

        $this->assertDatabaseHas('notifications', [
            'user_id' => $appointment->customer_id,
            'type' => NotificationType::BOOKING_CONFIRMED,
        ]);

        // The salon side: the provider is told the slot is theirs, and the owner
        // is told the salon has a booking — otherwise they find out by opening
        // the app. The provider is only notified once, even though both the
        // provider and the owner are addressed.
        $this->assertSame(1, Notification::where('user_id', $providerUser->id)->where('type', NotificationType::NEW_BOOKING)->count());

        if ($owner->id !== $providerUser->id) {
            $this->assertSame(1, Notification::where('user_id', $owner->id)->where('type', NotificationType::NEW_BOOKING)->count());
        }
    }

    public function test_a_reminder_is_written_once_however_many_times_the_window_is_swept(): void
    {
        [$appointment] = $this->bookingWithSalon();
        $notifications = app(NotificationService::class);

        $key = 'reminder:'.$appointment->id.':'.$appointment->appointment_date;

        $first = $notifications->appointmentReminder($appointment, 'Glow Studio', 'Sep 14, 2026 at 10:00 AM', $key);
        $second = $notifications->appointmentReminder($appointment, 'Glow Studio', 'Sep 14, 2026 at 10:00 AM', $key);

        $this->assertNotNull($first);
        $this->assertNull($second, 'A second sweep of the same window must produce no second reminder.');
        $this->assertSame(1, Notification::where('dedupe_key', $key)->count());
    }

    public function test_the_reminder_command_does_nothing_when_reminders_are_switched_off(): void
    {
        config(['services.push.appointment_reminder_lead_hours' => 0]);

        $this->artisan('app:send-appointment-reminders')
            ->expectsOutputToContain('Appointment reminders are disabled')
            ->assertSuccessful();

        $this->assertSame(0, Notification::where('type', NotificationType::APPOINTMENT_REMINDER)->count());
    }

    public function test_the_reminder_command_reports_what_it_would_do_without_sending_it(): void
    {
        config(['services.push.appointment_reminder_lead_hours' => 3]);

        [$appointment] = $this->bookingWithSalon();
        $appointment->update([
            'appointment_date' => now()->format('Y-m-d'),
            'start_time' => now()->addHour()->format('H:i:s'),
            'status' => 'scheduled',
        ]);

        $before = Notification::where('type', NotificationType::APPOINTMENT_REMINDER)->count();

        $this->artisan('app:send-appointment-reminders --dry-run')->assertSuccessful();

        $this->assertSame(
            $before,
            Notification::where('type', NotificationType::APPOINTMENT_REMINDER)->count(),
            'A dry run must not notify anybody.',
        );
    }

    public function test_the_reminder_command_sends_one_reminder_for_an_appointment_inside_the_window(): void
    {
        config(['services.push.appointment_reminder_lead_hours' => 3]);

        [$appointment] = $this->bookingWithSalon();
        $appointment->update([
            'appointment_date' => now()->format('Y-m-d'),
            'start_time' => now()->addHour()->format('H:i:s'),
            'status' => 'scheduled',
        ]);

        Queue::fake();

        $this->artisan('app:send-appointment-reminders')->assertSuccessful();
        $this->artisan('app:send-appointment-reminders')->assertSuccessful();

        $this->assertSame(
            1,
            Notification::where('type', NotificationType::APPOINTMENT_REMINDER)
                ->where('user_id', $appointment->customer_id)
                ->count(),
            'Two runs inside one window must still produce exactly one reminder.',
        );
    }

    public function test_the_reminder_command_ignores_a_booking_outside_the_window(): void
    {
        config(['services.push.appointment_reminder_lead_hours' => 3]);

        [$appointment] = $this->bookingWithSalon();
        $appointment->update([
            // Tomorrow morning: a booking that exists, but not one that is due
            // a reminder yet. Reminding now would be a push about nothing.
            'appointment_date' => now()->addDay()->format('Y-m-d'),
            'start_time' => '09:00:00',
            'status' => 'scheduled',
        ]);

        $this->artisan('app:send-appointment-reminders')->assertSuccessful();

        $this->assertSame(0, Notification::where('type', NotificationType::APPOINTMENT_REMINDER)->count());
    }

    public function test_the_reminder_command_skips_a_booking_that_has_not_been_paid_for(): void
    {
        config(['services.push.appointment_reminder_lead_hours' => 3]);

        [$appointment] = $this->bookingWithSalon();
        $appointment->update([
            'appointment_date' => now()->format('Y-m-d'),
            'start_time' => now()->addHour()->format('H:i:s'),
            'status' => 'pending_payment',
        ]);

        $this->artisan('app:send-appointment-reminders')->assertSuccessful();

        $this->assertSame(0, Notification::where('type', NotificationType::APPOINTMENT_REMINDER)->count());
    }

    public function test_the_no_show_sweep_notifies_only_the_appointments_it_just_swept(): void
    {
        [$swept] = $this->bookingWithSalon();
        [$historic] = $this->bookingWithSalon();

        foreach ([$swept, $historic] as $appointment) {
            $appointment->update([
                'appointment_date' => now()->subDays(3)->format('Y-m-d'),
                'status' => 'scheduled',
            ]);
        }

        // The historic one is swept first, on its own.
        $this->artisan('app:mark-no-shows')->assertSuccessful();
        $first = Notification::where('user_id', $historic->customer_id)->count();
        $this->assertSame(1, $first);

        $historic->update(['status' => 'scheduled']);
        $this->artisan('app:mark-no-shows')->assertSuccessful();

        $this->assertSame(
            1,
            Notification::where('user_id', $historic->customer_id)->count(),
            'Re-running the sweep must not re-notify about a visit the customer already heard about.',
        );

        $this->assertSame(1, Notification::where('user_id', $swept->customer_id)->count());
    }

    public function test_a_walk_in_with_no_account_is_swept_without_anybody_to_tell(): void
    {
        [$appointment] = $this->bookingWithSalon();
        $appointment->update([
            'customer_id' => null,
            'walk_in_customer_name' => 'Walk In',
            'walk_in_customer_phone' => '9999999999',
            'appointment_date' => now()->subDays(2)->format('Y-m-d'),
            'status' => 'scheduled',
        ]);

        $this->artisan('app:mark-no-shows')
            ->expectsOutputToContain('Marked')
            ->assertSuccessful();

        $this->assertSame('no_show', $appointment->fresh()->status);
    }

    public function test_every_real_event_produces_a_row_with_an_action_that_routes(): void
    {
        $service = app(NotificationService::class);
        [$appointment] = $this->bookingWithSalon();

        $events = [
            fn () => $service->bookingAwaitingPayment($appointment, 'Glow Studio', 500.0),
            fn () => $service->bookingConfirmed($appointment, 'Glow Studio', 'Sep 14, 2026 at 10:00 AM'),
            fn () => $service->bookingCancelled($appointment, 'Glow Studio', 'Sep 14, 2026 at 10:00 AM'),
            fn () => $service->bookingRescheduled($appointment, 'Glow Studio', 'Sep 14, 2026 at 10:00 AM'),
            fn () => $service->appointmentReminder($appointment, 'Glow Studio', 'Sep 14, 2026 at 10:00 AM', 'k1'),
            fn () => $service->appointmentMarkedNoShow($appointment, 'Glow Studio', 'k2'),
            fn () => $service->appointmentCompleted($appointment, 'Glow Studio', 'k3'),
            fn () => $service->providerAppointmentRescheduled($appointment),
        ];

        foreach ($events as $index => $event) {
            $notification = $event();

            $this->assertNotNull($notification, "Event {$index} wrote no notification.");
            $this->assertNotNull(
                $notification->action,
                "Event {$index} wrote a notification the app cannot route.",
            );
            $this->assertNotNull(
                NotificationType::defaultActionFor((string) $notification->type),
                "Event {$index} used a type with no default action.",
            );
        }
    }

    public function test_a_walk_in_booking_tells_the_salon_and_nobody_else(): void
    {
        [$appointment, $owner] = $this->bookingWithSalon();
        $appointment->update(['customer_id' => null, 'walk_in_customer_name' => 'Walk In']);

        app(NotificationService::class)->notifySalonOfNewBooking($appointment, 'Glow Studio', 'Sep 14, 2026 at 10:00 AM');

        $this->assertDatabaseHas('notifications', [
            'user_id' => $owner->id,
            'type' => NotificationType::NEW_BOOKING,
        ]);

        // There is no customer account, so there is nothing to send a customer
        // notification to — and nothing should be invented for one.
        $this->assertSame(0, Notification::where('related_appointment_id', $appointment->id)
            ->where('type', NotificationType::BOOKING_CONFIRMED)->count());
    }

    public function test_a_notification_with_nobody_to_notify_is_not_an_error(): void
    {
        [$appointment] = $this->bookingWithSalon();
        $appointment->update(['customer_id' => null, 'walk_in_customer_name' => 'Walk In']);

        $result = app(NotificationService::class)->bookingConfirmed($appointment, 'Glow Studio', 'Sep 14, 2026 at 10:00 AM');

        $this->assertNull($result);
    }

    // -- F. The delivery ledger ---------------------------------------------

    public function test_the_ledger_records_where_a_push_went_without_the_token(): void
    {
        $user = $this->customer();
        $device = $this->device($user);
        $notification = $this->notification($user);

        (new SendPushNotificationJob($notification->id))->handle(
            $this->fakeGateway([$device->id => PushResult::accepted('test', 'msg-1')])
        );

        $delivery = NotificationDelivery::where('notification_id', $notification->id)->first();

        $this->assertNotNull($delivery);
        $this->assertNotSame(self::TOKEN, $delivery->destination);
        $this->assertSame(NotificationDelivery::CHANNEL_PUSH, $delivery->channel);
        $this->assertSame(1, (int) $delivery->attempt_count);
    }

    public function test_writing_a_notification_through_the_service_queues_its_push(): void
    {
        Queue::fake();

        [$appointment] = $this->bookingWithSalon();

        app(NotificationService::class)->bookingConfirmed($appointment, 'Glow Studio', 'Sep 14, 2026 at 10:00 AM');

        // A notification written without a push is the one way this pipeline
        // silently stops existing for a new event, so the wiring is asserted
        // rather than assumed.
        Queue::assertPushed(SendPushNotificationJob::class);
    }

    // -- Fixtures -----------------------------------------------------------

    /**
     * A real FCM gateway whose access token is stubbed.
     *
     * The signing and the token exchange are FcmAccessTokenProvider's job and
     * are exercised against Google's own endpoint shape in
     * FcmAccessTokenProviderTest; here they are noise between the test and the
     * thing under test, which is how the gateway turns an HTTP answer into a
     * delivery verdict. A generated key would also be a poor dependency: key
     * generation needs an openssl.cnf that is not present on every machine that
     * runs this suite, so the tests would fail for a reason that has nothing to
     * do with notifications.
     */
    private function gateway(): FcmPushGateway
    {
        $credentials = new FcmCredentials('bookalook-test', 'test@example.iam.gserviceaccount.com', 'unused-in-these-tests');

        return new FcmPushGateway($credentials, new StubbedFcmAccessTokenProvider($credentials));
    }

    /**
     * A gateway that answers from a fixed script, one result per device.
     *
     * $results is keyed by UserDevice id; any device with no entry is reported
     * as failed, so a test that forgets to stub a device sees that rather than
     * seeing a silent success. $sentTo records who was addressed, which is how
     * a test proves a retry did not re-send to a phone that already worked.
     */
    private function fakeGateway(array $results): PushGateway
    {
        return new class($results) implements PushGateway
        {
            public array $sentTo = [];

            public function __construct(private array $results)
            {
            }

            public function send(iterable $devices, PushPayload $payload): array
            {
                $out = [];

                foreach ($devices as $device) {
                    $this->sentTo[] = $device->id;

                    $out[$device->id] = $this->results[$device->id]
                        ?? PushResult::failed('test', 'No stubbed result for this device.');
                }

                return $out;
            }
        };
    }

    private function user(string $role): User
    {
        return User::create([
            'role' => $role,
            'name' => 'Test '.$role,
            'phone' => (string) random_int(6000000000, 9999999999),
            'password_hash' => bcrypt('secret'),
        ]);
    }

    private function customer(): User
    {
        return $this->user('customer');
    }

    private function registerDevice(User $user, array $overrides = [])
    {
        return $this->actingAs($user, 'sanctum')->postJson('/api/customer/devices/register', array_merge([
            'app_type' => 'customer_app',
            'platform' => 'android',
            'push_token' => self::TOKEN,
            'app_version' => '1.4.2',
        ], $overrides));
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
            'type' => NotificationType::BOOKING_CONFIRMED,
            'title' => 'Booking confirmed',
            'message' => 'Your booking is confirmed.',
            'data' => ['action' => 'view_appointment'],
            'is_read' => false,
        ], $overrides));
    }

    private function booking(User $customer): Appointment
    {
        return $this->bookingWithSalon($customer)[0];
    }

    /**
     * @return array{0: Appointment, 1: User, 2: User}
     */
    private function bookingWithSalon(?User $customer = null): array
    {
        $owner = $this->user('admin');

        $salon = Salon::create([
            'admin_id' => $owner->id,
            'name' => 'Glow Studio',
            'slug' => 'glow-studio-'.Str::lower(Str::random(8)),
            'address' => '1 Test Street',
            'submitted_by' => $owner->id,
        ]);

        $providerUser = $this->user('service_provider');
        $provider = ServiceProvider::create(['user_id' => $providerUser->id, 'salon_id' => $salon->id]);

        $appointment = Appointment::create([
            'salon_id' => $salon->id,
            'customer_id' => ($customer ?? $this->customer())->id,
            'appointed_provider_id' => $provider->id,
            'appointment_date' => '2026-09-14',
            'start_time' => '10:00:00',
            'end_time' => '11:00:00',
            'status' => 'scheduled',
        ]);

        return [$appointment->fresh(['salon', 'customer', 'appointedProvider']), $owner, $providerUser];
    }
}
