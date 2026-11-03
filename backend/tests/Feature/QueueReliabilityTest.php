<?php

namespace Tests\Feature;

use App\Jobs\DispatchCampaignJob;
use App\Jobs\RetryPendingPushDeliveryJob;
use App\Jobs\SendCampaignMessageJob;
use App\Jobs\SendPushNotificationJob;
use App\Jobs\SendSalonSyncJob;
use App\Jobs\SendWhatsAppMessageJob;
use App\Models\Campaign;
use App\Models\CampaignRecipient;
use App\Models\CampaignTemplate;
use App\Models\Notification;
use App\Models\NotificationDelivery;
use App\Models\Salon;
use App\Models\User;
use App\Models\UserDevice;
use App\Models\WhatsAppMessage;
use App\Services\Notifications\PushGateway;
use App\Services\Notifications\PushPayload;
use App\Services\Notifications\PushResult;
use App\Services\Notifications\WhatsAppGateway;
use App\Support\SafeDispatch;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Queue\NullQueue;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Phase 4: queue assignment, retry/timeout policy, no duplicate external
 * sends, recovery from lost jobs (PostgreSQL rows are the record), and queue
 * outages never failing a committed business operation.
 *
 * Runs on SQLite with fakes. Real-Redis behaviour (blocking pop, retry_after,
 * killed workers) is checked on the VPS during the cutover (see runbook).
 */
class QueueReliabilityTest extends TestCase
{
    use DatabaseTransactions;

    private string $u;

    protected function setUp(): void
    {
        parent::setUp();
        $this->u = substr(bin2hex(random_bytes(6)), 0, 8);
    }

    private function user(string $role = 'customer'): User
    {
        return User::create([
            'id' => (string) Str::uuid(), 'role' => $role, 'name' => "U {$this->u}",
            'phone' => '7'.random_int(100000000, 999999999), 'password_hash' => 'x', 'is_active' => true,
        ]);
    }

    private function whatsapp(array $over = []): WhatsAppMessage
    {
        return WhatsAppMessage::create($over + [
            'to_phone' => '9876543210', 'template' => 'bookalook_booking_confirmed',
            'payload' => ['parameters' => ['x']], 'status' => WhatsAppMessage::STATUS_QUEUED,
        ]);
    }

    private function notification(User $user, array $over = []): Notification
    {
        return Notification::create($over + [
            'user_id' => $user->id, 'type' => 'salon_closure', 'title' => 'T', 'message' => 'M',
            'data' => ['action' => 'reschedule_appointment'], 'is_read' => false,
        ]);
    }

    private function device(User $user): UserDevice
    {
        return UserDevice::create([
            'user_id' => $user->id, 'app_type' => 'customer_app', 'platform' => 'android',
            'push_token' => 'tok-'.$this->u.Str::random(20), 'app_version' => '1.0.0', 'is_active' => true, 'last_active_at' => now(),
        ]);
    }

    private function countingWhatsApp(): object
    {
        $gateway = new class implements WhatsAppGateway {
            public int $sent = 0;

            public function send(WhatsAppMessage $message): void
            {
                $this->sent++;
                $message->increment('attempts');
                $message->forceFill(['status' => WhatsAppMessage::STATUS_SENT, 'sent_at' => now()])->save();
            }
        };
        $this->app->instance(WhatsAppGateway::class, $gateway);

        return $gateway;
    }

    private function countingPush(?PushResult $result = null): object
    {
        $gateway = new class($result) implements PushGateway {
            public int $calls = 0;

            public function __construct(private ?PushResult $result) {}

            public function send(iterable $devices, PushPayload $payload): array
            {
                $this->calls++;
                $out = [];
                foreach ($devices as $d) {
                    $out[$d->id] = $this->result ?? PushResult::accepted('fcm', 'm-'.$d->id);
                }

                return $out;
            }
        };
        $this->app->instance(PushGateway::class, $gateway);

        return $gateway;
    }

    private function campaign(array $over = []): Campaign
    {
        $owner = $this->user('admin');
        $k = $this->u.Str::lower(Str::random(5));
        $salon = Salon::create(['id' => (string) Str::uuid(), 'admin_id' => $owner->id, 'name' => "S {$k}", 'slug' => "s-{$k}", 'address' => 'x', 'submitted_by' => $owner->id, 'status' => 'active']);
        $template = CampaignTemplate::create(['id' => (string) Str::uuid(), 'key' => "k{$k}", 'name' => 'T', 'category' => 'marketing', 'meta_template_name' => 'promo', 'body_preview' => 'Hi', 'is_active' => true]);

        return Campaign::create($over + ['id' => (string) Str::uuid(), 'salon_id' => $salon->id, 'campaign_template_id' => $template->id, 'name' => 'C', 'status' => Campaign::STATUS_SENDING]);
    }

    /** A queue connection whose every push fails like an unreachable Redis. */
    private function breakQueue(): void
    {
        Queue::extend('broken', fn () => new class implements \Illuminate\Queue\Connectors\ConnectorInterface {
            public function connect(array $config)
            {
                return new class extends NullQueue {
                    public function push($job, $data = '', $queue = null) { throw new \RuntimeException('Connection refused'); }
                    public function later($delay, $job, $data = '', $queue = null) { throw new \RuntimeException('Connection refused'); }
                };
            }
        });
        config(['queue.connections.broken' => ['driver' => 'broken'], 'queue.default' => 'broken']);
    }

    // --- Queue assignment and policy -------------------------------------------

    public function test_each_job_goes_to_its_queue(): void
    {
        $otp = $this->whatsapp(['category' => 'authentication']);
        $promo = $this->whatsapp(['category' => WhatsAppMessage::CATEGORY_MARKETING]);
        $booking = $this->whatsapp(['category' => WhatsAppMessage::CATEGORY_UTILITY]);

        $this->assertSame('critical', (new SendWhatsAppMessageJob($otp->id))->queue);
        $this->assertSame('marketing', (new SendWhatsAppMessageJob($promo->id))->queue);
        $this->assertSame('notifications', (new SendWhatsAppMessageJob($booking->id))->queue);
        $this->assertSame('notifications', (new SendPushNotificationJob((string) Str::uuid()))->queue);
        $this->assertSame('notifications', (new RetryPendingPushDeliveryJob((string) Str::uuid()))->queue);
        $this->assertSame('notifications', (new SendSalonSyncJob((string) Str::uuid()))->queue);
        $this->assertSame('marketing', (new DispatchCampaignJob((string) Str::uuid()))->queue);
        $this->assertSame('marketing', (new SendCampaignMessageJob((string) Str::uuid()))->queue);
    }

    public function test_every_job_timeout_is_below_retry_after(): void
    {
        $retryAfter = (int) config('queue.connections.redis.retry_after');
        $this->assertSame('state', config('queue.connections.redis.connection'));
        $this->assertSame(5, config('queue.connections.redis.block_for'));

        foreach ([SendWhatsAppMessageJob::class, SendPushNotificationJob::class, RetryPendingPushDeliveryJob::class,
                  SendSalonSyncJob::class, DispatchCampaignJob::class, SendCampaignMessageJob::class] as $class) {
            $timeout = (new \ReflectionClass($class))->getDefaultProperties()['timeout'] ?? null;
            $this->assertNotNull($timeout, "{$class} declares a timeout");
            $this->assertLessThan($retryAfter, $timeout, "{$class} timeout {$timeout}s < retry_after {$retryAfter}s");
        }
    }

    public function test_failed_jobs_are_kept_in_the_database(): void
    {
        $this->assertSame('database-uuids', config('queue.failed.driver'));
        $this->assertSame('failed_jobs', config('queue.failed.table'));
    }

    // --- WhatsApp: no second send after an interrupted one ----------------------------

    public function test_a_whatsapp_send_that_was_interrupted_is_not_sent_again(): void
    {
        $gateway = $this->countingWhatsApp();
        $message = $this->whatsapp(['attempts' => 1]); // provider called, result never saved

        (new SendWhatsAppMessageJob($message->id))->handle($gateway, app(\App\Services\InvoicePdfService::class));

        $this->assertSame(0, $gateway->sent);
        $this->assertSame(WhatsAppMessage::STATUS_FAILED, $message->fresh()->status);
        $this->assertSame(WhatsAppMessage::OUTCOME_UNKNOWN, $message->fresh()->error);
    }

    public function test_a_never_attempted_whatsapp_is_sent_once(): void
    {
        $gateway = $this->countingWhatsApp();
        $message = $this->whatsapp();
        $job = new SendWhatsAppMessageJob($message->id);

        $job->handle($gateway, app(\App\Services\InvoicePdfService::class));
        $job->handle($gateway, app(\App\Services\InvoicePdfService::class)); // duplicate delivery of the job

        $this->assertSame(1, $gateway->sent);
    }

    // --- Push: recovery marker and no re-send -------------------------------------------

    public function test_a_push_job_marks_its_notification_done_whether_sent_or_skipped(): void
    {
        $gateway = $this->countingPush();
        $withDevice = $this->user();
        $this->device($withDevice);
        $sent = $this->notification($withDevice, ['push_queued_at' => now()]);
        $noDevice = $this->notification($this->user(), ['push_queued_at' => now()]);

        (new SendPushNotificationJob($sent->id))->handle($gateway);
        (new SendPushNotificationJob($noDevice->id))->handle($gateway);

        $this->assertNotNull($sent->fresh()->push_done_at);
        $this->assertNotNull($noDevice->fresh()->push_done_at);
        $this->assertSame(1, $gateway->calls);
    }

    public function test_a_push_already_done_is_not_sent_again(): void
    {
        $gateway = $this->countingPush();
        $user = $this->user();
        $this->device($user);
        $n = $this->notification($user, ['push_queued_at' => now(), 'push_done_at' => now()]);

        (new SendPushNotificationJob($n->id))->handle($gateway);

        $this->assertSame(0, $gateway->calls);
    }

    public function test_the_push_carries_a_tag_so_a_repeat_replaces_rather_than_stacks(): void
    {
        $user = $this->user();
        $n = $this->notification($user);
        // Built without credentials: only the message shape is under test.
        $gateway = (new \ReflectionClass(\App\Services\Notifications\FcmPushGateway::class))->newInstanceWithoutConstructor();
        $build = new \ReflectionMethod($gateway, 'messageFor');

        $message = $build->invoke($gateway, 'token', PushPayload::fromNotification($n));

        $this->assertSame((string) $n->id, $message['android']['notification']['tag']);
        $this->assertSame((string) $n->id, $message['apns']['headers']['apns-collapse-id']);
    }

    // --- Recovery sweep -------------------------------------------------------------------

    public function test_a_lost_push_is_queued_again_once_per_sweep_and_given_up_after_three(): void
    {
        Queue::fake();
        $user = $this->user();
        $lost = $this->notification($user, ['push_queued_at' => now()->subMinutes(6)]);
        $fresh = $this->notification($user, ['push_queued_at' => now()->subMinutes(2)]);
        $done = $this->notification($user, ['push_queued_at' => now()->subMinutes(30), 'push_done_at' => now()]);
        $legacy = $this->notification($user); // written before tracking existed

        $this->artisan('app:recover-queued-work')->assertSuccessful();
        Queue::assertPushedOn('notifications', SendPushNotificationJob::class, fn ($j) => $j->notificationId === $lost->id);
        Queue::assertPushed(SendPushNotificationJob::class, 1);
        $this->assertSame(1, $lost->fresh()->push_sweeps);

        // Straight away again: its clock was reset, so nothing is re-queued.
        $this->artisan('app:recover-queued-work')->assertSuccessful();
        Queue::assertPushed(SendPushNotificationJob::class, 1);

        // Third sweep already used up: given up, logged, not queued.
        $lost->forceFill(['push_sweeps' => 3, 'push_queued_at' => now()->subMinutes(6)])->save();
        $this->artisan('app:recover-queued-work')->assertSuccessful();
        Queue::assertPushed(SendPushNotificationJob::class, 1);
        $this->assertNotNull($lost->fresh()->push_done_at);

        $this->assertNull($fresh->fresh()->push_done_at);
        $this->assertSame(0, $legacy->fresh()->push_sweeps);
    }

    public function test_a_pending_delivery_whose_retry_was_lost_is_retried_or_finally_failed(): void
    {
        Queue::fake();
        $user = $this->user();
        $device = $this->device($user);
        $make = fn (int $attempts) => NotificationDelivery::create([
            'notification_id' => $this->notification($user)->id, 'user_device_id' => $device->id,
            'channel' => NotificationDelivery::CHANNEL_PUSH, 'status' => NotificationDelivery::STATUS_PENDING,
            'provider' => 'fcm', 'destination' => 'x', 'attempt_count' => $attempts,
        ]);
        $stuck = $make(2);
        $exhausted = $make(6);
        NotificationDelivery::whereKey([$stuck->id, $exhausted->id])->update(['updated_at' => now()->subMinutes(10)]);

        $this->artisan('app:recover-queued-work')->assertSuccessful();

        Queue::assertPushed(RetryPendingPushDeliveryJob::class, fn ($j) => $j->deliveryId === $stuck->id);
        Queue::assertPushed(RetryPendingPushDeliveryJob::class, 1);
        $this->assertSame(NotificationDelivery::STATUS_FAILED, $exhausted->fresh()->status);
    }

    public function test_an_interrupted_whatsapp_is_marked_unknown_not_resent(): void
    {
        Queue::fake();
        $interrupted = $this->whatsapp(['attempts' => 1]);
        $neverTried = $this->whatsapp();
        WhatsAppMessage::whereKey([$interrupted->id, $neverTried->id])->update(['updated_at' => now()->subMinutes(20)]);

        $this->artisan('app:recover-queued-work')->assertSuccessful();

        $this->assertSame(WhatsAppMessage::OUTCOME_UNKNOWN, $interrupted->fresh()->error);
        $this->assertSame(WhatsAppMessage::STATUS_QUEUED, $neverTried->fresh()->status, 'left for the outbox drain');
        Queue::assertNotPushed(SendWhatsAppMessageJob::class);
    }

    public function test_an_overdue_scheduled_campaign_is_started(): void
    {
        Queue::fake();
        $campaign = $this->campaign(['status' => Campaign::STATUS_SCHEDULED, 'scheduled_for' => now()->subMinutes(10)]);
        $future = $this->campaign(['status' => Campaign::STATUS_SCHEDULED, 'scheduled_for' => now()->addDay()]);

        $this->artisan('app:recover-queued-work')->assertSuccessful();

        Queue::assertPushedOn('marketing', DispatchCampaignJob::class, fn ($j) => $j->campaignId === $campaign->id);
        Queue::assertNotPushed(DispatchCampaignJob::class, fn ($j) => $j->campaignId === $future->id);
    }

    public function test_the_dry_run_changes_nothing(): void
    {
        Queue::fake();
        $n = $this->notification($this->user(), ['push_queued_at' => now()->subMinutes(6)]);

        $this->artisan('app:recover-queued-work', ['--dry-run' => true])->assertSuccessful();

        Queue::assertNothingPushed();
        $this->assertSame(0, $n->fresh()->push_sweeps);
    }

    // --- Campaigns: never twice ----------------------------------------------------------

    public function test_two_copies_of_a_campaign_send_message_one_recipient_once(): void
    {
        $gateway = $this->countingWhatsApp();
        $campaign = $this->campaign(['started_at' => now()]);
        $recipient = CampaignRecipient::create(['campaign_id' => $campaign->id, 'phone' => '9876543210', 'status' => CampaignRecipient::STATUS_PENDING]);

        (new SendCampaignMessageJob($recipient->id))->handle($gateway);
        (new SendCampaignMessageJob($recipient->id))->handle($gateway);

        $this->assertSame(1, $gateway->sent);
        $this->assertSame(1, WhatsAppMessage::where('campaign_id', $campaign->id)->count());
    }

    public function test_a_campaign_is_started_only_once(): void
    {
        Queue::fake();
        $campaign = $this->campaign(['status' => Campaign::STATUS_SCHEDULED, 'scheduled_for' => now()->subMinute()]);
        $service = app(\App\Services\Marketing\CampaignService::class);

        (new DispatchCampaignJob($campaign->id))->handle($service);
        $startedAt = $campaign->fresh()->started_at;
        $this->travel(5)->seconds();
        (new DispatchCampaignJob($campaign->id))->handle($service);

        $this->assertEquals($startedAt, $campaign->fresh()->started_at, 'the second copy did not start it again');
        $this->assertNotSame(Campaign::STATUS_FAILED, $campaign->fresh()->status);
    }

    public function test_the_campaign_job_is_unique_per_campaign(): void
    {
        $job = new DispatchCampaignJob('abc');
        $this->assertInstanceOf(\Illuminate\Contracts\Queue\ShouldBeUnique::class, $job);
        $this->assertSame('abc', $job->uniqueId());
    }

    // --- Queue outage --------------------------------------------------------------------

    public function test_a_queue_outage_never_fails_the_committed_work_and_is_logged(): void
    {
        $this->breakQueue();
        Log::spy();
        $message = null;

        DB::transaction(function () use (&$message) {
            $message = $this->whatsapp();
            SafeDispatch::afterCommit(new SendWhatsAppMessageJob($message->id), ['whatsapp_message_id' => $message->id]);
        });

        $this->assertNotNull(WhatsAppMessage::find($message->id), 'the outbox row committed');
        $this->assertSame(WhatsAppMessage::STATUS_QUEUED, $message->fresh()->status, 'left for the drain to pick up');
        Log::shouldHaveReceived('error')->withArgs(fn ($event) => $event === 'queue.dispatch_failed');
    }

    public function test_a_queue_outage_does_not_fail_a_booking_change(): void
    {
        $this->breakQueue();
        $appointment = new \App\Models\Appointment(['salon_id' => (string) Str::uuid()]);
        $appointment->id = (string) Str::uuid();

        (new \ReflectionMethod(\App\Models\Appointment::class, 'nudgeSalon'))->invoke($appointment);

        $this->addToAssertionCount(1); // no exception
    }

    public function test_a_queue_outage_while_queueing_a_push_leaves_it_owed_for_recovery(): void
    {
        $this->breakQueue();
        $user = $this->user();

        $notification = $this->notification($user);
        $mirror = new \ReflectionMethod(\App\Services\Notifications\NotificationService::class, 'mirrorToPush');
        $mirror->invoke(app(\App\Services\Notifications\NotificationService::class), $notification);

        $fresh = $notification->fresh();
        $this->assertNotNull($fresh->push_queued_at, 'recorded as owed');
        $this->assertNull($fresh->push_done_at, 'so the sweep will find it');
    }
}
