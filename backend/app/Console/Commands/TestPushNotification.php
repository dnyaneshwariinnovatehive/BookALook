<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Models\UserDevice;
use App\Services\Notifications\NotificationService;
use Illuminate\Console\Command;

class TestPushNotification extends Command
{
    protected $signature = 'notifications:test {user_id : The ID of the user to send the test notification to}';

    protected $description = 'Send a diagnostic test notification to all active devices of a user.';

    public function handle(NotificationService $notifications)
    {
        $userId = $this->argument('user_id');

        $user = User::find($userId);

        if (! $user) {
            $this->error("User not found with ID: {$userId}");
            return 1;
        }

        $devicesCount = UserDevice::query()
            ->where('user_id', $user->id)
            ->pushable()
            ->count();

        $this->info("Recipient user ID: {$user->id}");
        $this->info("Number of active devices found: {$devicesCount}");

        if ($devicesCount === 0) {
            $this->warn('No active push devices registered.');
            // We still proceed to create the inbox row as requested by requirements.
        }

        // Using a non-existent type 'diagnostic_test' deliberately. 
        // In NotificationType, unknown types resolve to CATEGORY_TRANSACTIONAL (not suppressible) 
        // and audienceAppFor returns null (targets both Customer and Partner apps).
        $notification = $notifications->send(
            recipient: $user,
            type: 'diagnostic_test',
            title: 'BookALook Test Notification',
            message: 'This is a test notification from the BookALook notification system.',
        );

        if ($notification) {
            $this->info("Notification ID: {$notification->id}");
            $this->info("Queue dispatch status: Dispatched");
            return 0;
        }

        $this->error("Failed to create notification.");
        return 1;
    }
}
