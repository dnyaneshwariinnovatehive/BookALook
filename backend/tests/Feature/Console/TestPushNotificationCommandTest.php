<?php

namespace Tests\Feature\Console;

use App\Models\Notification;
use App\Models\User;
use App\Models\UserDevice;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\Queue;
use App\Jobs\SendPushNotificationJob;
use Tests\TestCase;

class TestPushNotificationCommandTest extends TestCase
{
    use DatabaseTransactions;

    public function test_it_creates_notification_and_dispatches_job_when_no_devices_exist(): void
    {
        Queue::fake();

        $user = User::create([
            'role' => 'customer',
            'name' => 'Test Customer',
            'phone' => (string) random_int(6000000000, 9999999999),
            'password_hash' => bcrypt('secret'),
        ]);

        $this->artisan("notifications:test {$user->id}")
            ->expectsOutput("Recipient user ID: {$user->id}")
            ->expectsOutput("Number of active devices found: 0")
            ->expectsOutput("No active push devices registered.")
            ->expectsOutput("Queue dispatch status: Dispatched")
            ->assertSuccessful();

        $this->assertDatabaseHas('notifications', [
            'user_id' => $user->id,
            'type' => 'diagnostic_test',
            'title' => 'BookALook Test Notification',
        ]);

        $notification = Notification::where('user_id', $user->id)->first();

        Queue::assertPushed(SendPushNotificationJob::class, function ($job) use ($notification) {
            return $job->notificationId === $notification->id;
        });
    }

    public function test_it_reports_device_count_and_dispatches_job_when_devices_exist(): void
    {
        Queue::fake();

        $user = User::create([
            'role' => 'customer',
            'name' => 'Test Customer',
            'phone' => (string) random_int(6000000000, 9999999999),
            'password_hash' => bcrypt('secret'),
        ]);

        UserDevice::forceCreate([
            'user_id' => $user->id,
            'push_token' => 'dummy_token_1',
            'app_type' => 'customer_app',
            'platform' => 'ios',
            'app_version' => '1.0.0',
            'is_active' => true,
        ]);

        UserDevice::forceCreate([
            'user_id' => $user->id,
            'push_token' => 'dummy_token_2',
            'app_type' => 'partner_app',
            'platform' => 'android',
            'app_version' => '1.0.0',
            'is_active' => true,
        ]);

        $this->artisan("notifications:test {$user->id}")
            ->expectsOutput("Recipient user ID: {$user->id}")
            ->expectsOutput("Number of active devices found: 2")
            ->expectsOutput("Queue dispatch status: Dispatched")
            ->doesntExpectOutput("No active push devices registered.")
            ->assertSuccessful();

        $notification = Notification::where('user_id', $user->id)->first();
        
        Queue::assertPushed(SendPushNotificationJob::class, function ($job) use ($notification) {
            return $job->notificationId === $notification->id;
        });
    }

    public function test_it_fails_when_user_does_not_exist(): void
    {
        Queue::fake();

        $this->artisan("notifications:test 999999")
            ->expectsOutput("User not found with ID: 999999")
            ->assertFailed();

        Queue::assertNothingPushed();
    }
}
