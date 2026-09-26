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
 * Try again on exactly one phone that a provider would not take the first time.
 *
 * This exists because the two obvious alternatives are both wrong. Retrying the
 * whole SendPushNotificationJob re-sends to every device, so a customer with two
 * phones gets a second copy on the one that already worked. Retrying inside the
 * original job is worse: it re-sends to the same devices on the next attempt for
 * the same reason. A ledger row that says `pending` is a promise that somebody
 * will come back to that row, and this is that somebody — one row, one device,
 * one attempt.
 *
 * Holds the delivery id rather than the device, so a phone that was deactivated
 * in the meantime is noticed before anything is sent rather than after.
 */
class RetryPendingPushDeliveryJob implements ShouldQueue
{
    use Dispatchable;
    use InteractsWithQueue;
    use Queueable;
    use SerializesModels;

    /**
     * Attempts on this retry alone, on top of the original send. A provider that
     * is down stays down, and a job that retries forever is a queue that never
     * drains.
     */
    public int $tries = 3;

    public int $timeout = 60;

    public function __construct(
        public readonly string $deliveryId,
        public readonly int $attempt = 1,
    ) {
        $this->afterCommit = true;
    }

    public function handle(PushGateway $gateway): void
    {
        $delivery = NotificationDelivery::with(['notification', 'userDevice'])->find($this->deliveryId);

        // Somebody else already finished this row, or the notification or device
        // it referred to has since been removed. Either way there is nothing
        // left to retry, and re-sending would be a duplicate.
        if (! $delivery || $delivery->status !== NotificationDelivery::STATUS_PENDING) {
            return;
        }

        $notification = $delivery->notification;
        $device = $delivery->userDevice;

        if (! $notification || ! $device) {
            return;
        }

        if (! $device->is_active) {
            // The phone was signed off after the first attempt — the user
            // uninstalled, or the provider called the token dead. Retrying
            // would send to a device the user has left behind.
            $this->settle($delivery, PushResult::failed('unknown', 'The device was deactivated before this retry ran.'));

            return;
        }

        try {
            $result = $gateway->send(collect([$device]), PushPayload::fromNotification($notification))[$device->id] ?? null;
        } catch (\Throwable $exception) {
            // A gateway-wide failure is a queue concern, not a delivery verdict.
            // Let it propagate so Laravel re-runs this job on its backoff and
            // the row stays `pending` in the meantime, which is honest: we still
            // do not know whether it landed.
            throw $exception;
        }

        if (! $result) {
            $this->settle($delivery, PushResult::failed('unknown', 'The push gateway returned no result for this device.'));

            return;
        }

        if (! $result->accepted && $result->retryable && $this->attempt < $this->tries) {
            // Still a maybe. Keep the row pending and come back later, bounded by
            // the attempt count, so a provider that is merely slow is given a
            // second chance without becoming an infinite loop.
            $delivery->forceFill(['attempt_count' => $delivery->countAttempt()])->save();

            Log::info('Push delivery still retryable; scheduling another attempt', [
                'delivery_id' => $delivery->id,
                'notification_id' => $notification->id,
                'attempt' => $this->attempt,
            ]);

            static::dispatch($delivery->id, $this->attempt + 1)->delay(now()->addSeconds(60 * $this->attempt));

            return;
        }

        $this->settle($delivery, $result);
    }

    /**
     * Move the row off `pending` for good: sent, or failed with a reason worth
     * having in the ledger.
     */
    private function settle(NotificationDelivery $delivery, PushResult $result): void
    {
        $accepted = $result->accepted;

        $delivery->forceFill([
            'status' => $accepted ? NotificationDelivery::STATUS_SENT : NotificationDelivery::STATUS_FAILED,
            'provider' => $result->provider ?? $delivery->provider,
            'provider_message_id' => $result->messageId ?? $delivery->provider_message_id,
            'attempt_count' => $delivery->countAttempt(),
            'failure_reason' => $accepted
                ? null
                : ($result->failureReason ?? $delivery->failure_reason ?? 'The push gateway reported no result.'),
            'sent_at' => $accepted ? now() : $delivery->sent_at,
            'failed_at' => $accepted ? $delivery->failed_at : now(),
        ])->save();

        $device = $delivery->userDevice;

        if ($result->deactivateDevice && $device?->is_active) {
            $device->forceFill(['is_active' => false])->save();

            Log::info('Deactivated a device the push provider no longer recognises', [
                'delivery_id' => $delivery->id,
                'device_id' => $device->id,
                'user_id' => $device->user_id,
            ]);
        }
    }

    public function failed(?\Throwable $exception): void
    {
        $delivery = NotificationDelivery::find($this->deliveryId);

        if (! $delivery || $delivery->status !== NotificationDelivery::STATUS_PENDING) {
            return;
        }

        $this->settle($delivery, PushResult::failed('unknown', $exception?->getMessage() ?: 'The retry failed without a message.'));

        Log::error('Push delivery retry exhausted', [
            'delivery_id' => $delivery->id,
            'notification_id' => $delivery->notification_id,
            'attempts' => $this->attempt,
            'error' => $exception?->getMessage(),
        ]);
    }
}
