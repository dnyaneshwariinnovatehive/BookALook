<?php

namespace App\Services\Notifications;

use App\Models\UserDevice;
use Illuminate\Support\Facades\Log;

/**
 * Writes down what would have been pushed, and sends nothing.
 *
 * This is the driver that runs until a real one exists, and it is deliberately
 * honest about it. A push is only "sent" if a provider accepted it, so this
 * gateway accepts nothing — it reports a log id and the job marks the delivery
 * `sent`, which is a real outcome, not a pretend one. The alternative, marking
 * these `failed` or leaving them `pending`, would make the ledger cry wolf
 * every time the app registers a device.
 *
 * The other job it does is keeping the pipeline honest while the backend is
 * built ahead of the app: the notification service, the queue, the device
 * lookup and the ledger are all exercised end to end, and the only thing
 * missing is a network call. That is why the log carries the full context a
 * real send would — everything except the token.
 */
class LogPushGateway implements PushGateway
{
    public const PROVIDER = 'log';

    /**
     * {@inheritdoc}
     */
    public function send(iterable $devices, PushPayload $payload): array
    {
        $results = [];

        foreach ($devices as $device) {
            if (! $device->push_token) {
                continue;
            }

            Log::info('Push notification recorded by the log driver (nothing left this server)', [
                'provider' => self::PROVIDER,
                'notification_id' => $payload->notificationId,
                'user_id' => $device->user_id,
                'device_id' => $device->id,
                'app_type' => $device->app_type,
                'platform' => $device->platform,
                'device_model' => $device->device_model,
                'app_version' => $device->app_version,
                // Masked, deliberately. A push token is a bearer credential —
                // whoever holds it can put anything on that customer's screen —
                // and a log file is the one place this value is certain to
                // outlive the request.
                'device_token' => $device->maskedToken(),
                'type' => $payload->type,
                'title' => $payload->title,
                'message' => $payload->message,
                'action' => $payload->action,
                'deeplink' => $payload->deeplink(),
                'data' => $payload->data,
                'notification' => $payload->toNotificationArray(),
            ]);

            $results[$device->id] = PushResult::accepted(self::PROVIDER, 'log:'.$payload->notificationId);
        }

        return $results;
    }

    /**
     * Exposed for the one caller that needs to name the provider in a row.
     */
    public function provider(): string
    {
        return self::PROVIDER;
    }
}
