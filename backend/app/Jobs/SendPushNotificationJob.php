<?php

namespace App\Jobs;

use App\Models\Notification;
use App\Models\NotificationDelivery;
use App\Models\UserDevice;
use App\Services\Notifications\PushGateway;
use App\Services\Notifications\PushPayload;
use App\Services\Notifications\PushResult;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

/**
 * Mirror one inbox notification to the customer's phones.
 *
 * Deliberately holds a notification id and nothing else. Serialising the model
 * would re-read it from the database anyway, and a plain id means a job that
 * sat in the queue over lunch picks up the notification as it stands when it
 * finally runs rather than as it stood when it was queued.
 *
 * This job is fired for notifications that were already delivered to the inbox
 * by the time it runs, so it has no business touching the notifications table
 * beyond reading one row. A push that fails is a failed push, not a missing
 * notification.
 */
class SendPushNotificationJob implements ShouldQueue
{
    use Dispatchable;
    use InteractsWithQueue;
    use Queueable;
    use SerializesModels;

    /**
     * A phone that is asleep retries quietly. Three tries covers a network that
     * blinks without turning anything into a duplicate notice for a customer
     * who may well have already seen it in the app.
     */
    public int $tries = 3;

    /**
     * Comfortably inside the production worker's --timeout=90, so a slow
     * gateway loses its worker slot to a timeout rather than to a kill.
     */
    public int $timeout = 60;

    public int $backoff = 10;

    public function __construct(public readonly string $notificationId)
    {
        // Waiting for the transaction to commit is not a preference here, it is
        // the only correct order of operations: every caller creates the
        // notification inside DB::transaction(), and a worker that woke up early
        // would read a row that is not there yet. config/queue.php leaves
        // after_commit false for the marketing jobs, so this job opts in for
        // itself rather than relying on a connection default anything can
        // change — and NotificationService still states it at the call site.
        //
        // Assigned here rather than declared as `public $afterCommit = true`,
        // because the Queueable trait already declares that property and PHP
        // treats a redeclaration with a different initial value as an
        // incompatible trait composition — a fatal, not a warning.
        $this->afterCommit = true;
    }

    public function handle(PushGateway $gateway): void
    {
        $notification = Notification::find($this->notificationId);

        if (! $notification) {
            Log::warning('Push job found no notification to send; nothing to do', [
                'notification_id' => $this->notificationId,
            ]);

            return;
        }

        $devices = UserDevice::query()
            ->where('user_id', $notification->user_id)
            ->pushable()
            ->get();

        if ($devices->isEmpty()) {
            Log::info('No active device for this notification; it stays in the inbox only', [
                'notification_id' => $notification->id,
                'user_id' => $notification->user_id,
            ]);

            return;
        }

        $payload = PushPayload::fromNotification($notification);

        // Let a gateway-wide failure escape so the queue retries it. Per-device
        // outcomes come back as results and are recorded below; those are
        // answers, not exceptions, and retrying them would only re-send to the
        // phones that already worked.
        $results = $gateway->send($devices, $payload);

        foreach ($devices as $device) {
            $this->record($device, $payload, $results[$device->id] ?? null);
        }
    }

    /**
     * The retries are spent. Write down what never went out, so a support
     * question about a missing push has an answer waiting in the ledger instead
     * of silence.
     */
    public function failed(?\Throwable $exception): void
    {
        $notification = Notification::find($this->notificationId);

        if (! $notification) {
            return;
        }

        $reason = $exception?->getMessage() ?: 'The push job failed without a message.';

        Log::error('Push job failed after exhausting its retries', [
            'notification_id' => $notification->id,
            'user_id' => $notification->user_id,
            'attempts' => $this->attempts(),
            'error' => $reason,
        ]);

        $devices = UserDevice::query()
            ->where('user_id', $notification->user_id)
            ->pushable()
            ->get();

        foreach ($devices as $device) {
            // An earlier attempt may have reached this device before a later
            // attempt took the whole job down. That delivery did happen, and
            // overwriting it with a failure would be a lie in the other
            // direction.
            $alreadyRecorded = NotificationDelivery::query()
                ->where('notification_id', $notification->id)
                ->where('user_device_id', $device->id)
                ->exists();

            if ($alreadyRecorded) {
                continue;
            }

            $this->record($device, PushPayload::fromNotification($notification), PushResult::failed('unknown', $reason));
        }
    }

    /**
     * One row in the ledger per device, whatever the outcome.
     */
    private function record(UserDevice $device, PushPayload $payload, ?PushResult $result): void
    {
        $accepted = (bool) $result?->accepted;

        NotificationDelivery::create([
            'notification_id' => $payload->notificationId,
            'user_device_id' => $device->id,
            'channel' => NotificationDelivery::CHANNEL_PUSH,
            'status' => $accepted ? NotificationDelivery::STATUS_SENT : NotificationDelivery::STATUS_FAILED,
            'provider' => $result?->provider ?? 'unknown',
            'destination' => $device->maskedToken() ?? 'unknown',
            'provider_message_id' => $result?->messageId,
            'attempt_count' => max(1, $this->attempts()),
            'failure_reason' => $accepted ? null : ($result?->failureReason ?? 'The push gateway returned no result for this device.'),
            'sent_at' => $accepted ? now() : null,
            'failed_at' => $accepted ? null : now(),
        ]);

        // A provider that recognises a dead token is handing back an answer
        // that will not improve on its own. Signing the device off is the only
        // way the next notification stops paying to ask.
        if ($result?->deactivateDevice && $device->is_active) {
            $device->forceFill(['is_active' => false])->save();

            Log::info('Deactivated a device the push provider no longer recognises', [
                'notification_id' => $payload->notificationId,
                'device_id' => $device->id,
                'user_id' => $device->user_id,
            ]);
        }
    }
}
