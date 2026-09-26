<?php

namespace App\Services\Notifications;

use App\Models\UserDevice;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;

/**
 * Firebase Cloud Messaging over the HTTP v1 API.
 *
 * Speaks to FCM through Laravel's HTTP client rather than through a Firebase
 * SDK. The repository's runtime dependencies are four packages deep and adding
 * `kreait/firebase-php` would have brought an OAuth client, a Guzzle stack and a
 * gRPC extension along with it — a large, permanent dependency to express one
 * authenticated POST. Everything this gateway needs is a signed assertion and an
 * HTTP call, so both live in the two small collaborators beside it and the
 * dependency list stays where it is.
 *
 * HTTP v1 has no multicast. The legacy batch endpoint is gone, so one request
 * per device is the shape the provider actually offers, and that is what the
 * per-device result loop reflects. `PushGateway` was designed as many-to-one
 * precisely so this loop needed no reshaping at the call site.
 *
 * Failure handling is the part worth reading twice:
 *
 *   - A dead token (NOT_FOUND, or INVALID_ARGUMENT complaining about the token)
 *     is permanent. The device is signed off and no retry is attempted, because
 *     FCM will answer identically forever.
 *   - A rate limit, a 5xx, or a timeout is circumstantial. The device is left
 *     `pending` in the ledger and the rest of the send continues.
 *   - An auth or permission failure is not any one device's problem. It throws,
 *     so the queue retries the job and a single bad phone cannot hold up the
 *     other phones in the same notification.
 */
class FcmPushGateway implements PushGateway
{
    public const PROVIDER = 'fcm';

    /**
     * FCM's own ceiling. A user with more phones than this is a test account,
     * and silently ignoring the overflow is better than a partially delivered
     * notification with no record of what was dropped.
     */
    private const MAX_DEVICES_PER_SEND = 500;

    /**
     * FCM's ceiling on a single message, in bytes.
     *
     * Over the limit FCM answers 400 for every device, which is both wrong
     * (nothing is wrong with the phones) and expensive (one wasted request per
     * device). Refusing our own oversize message up front turns a fan-out of
     * failures into one loud error, and says which part of it is too big.
     */
    private const MAX_MESSAGE_BYTES = 4096;

    public function __construct(
        private FcmCredentials $credentials,
        private FcmAccessTokenProvider $tokens,
    ) {
    }

    /**
     * {@inheritdoc}
     */
    public function send(iterable $devices, PushPayload $payload): array
    {
        $this->assertWithinSizeLimit($payload);

        $results = [];
        $sent = 0;

        foreach ($devices as $device) {
            if (! $device->push_token) {
                continue;
            }

            if ($sent >= self::MAX_DEVICES_PER_SEND) {
                Log::warning('Truncating a push fan-out at the FCM device ceiling', [
                    'notification_id' => $payload->notificationId,
                    'user_id' => $device->user_id,
                ]);

                $results[$device->id] = PushResult::failed(
                    self::PROVIDER,
                    'Not attempted: this account has more registered devices than one message may address.',
                    false,
                    false
                );

                continue;
            }

            $sent++;
            $results[$device->id] = $this->sendToDevice($device, $payload);
        }

        return $results;
    }

    private function sendToDevice(UserDevice $device, PushPayload $payload): PushResult
    {
        $response = $this->post($device->push_token, $payload);

        if ($response->successful()) {
            return PushResult::accepted(
                self::PROVIDER,
                $response->json('name') // FCM's message name, e.g. projects/x/messages/0:1
            );
        }

        return $this->interpret($response, $device, $payload);
    }

    private function post(string $token, PushPayload $payload): Response
    {
        return Http::withToken($this->tokens->token())
            ->acceptJson()
            ->timeout(20)
            ->post($this->endpoint(), ['message' => $this->messageFor($token, $payload)]);
    }

    /**
     * The v1 message body.
     *
     * Both blocks are sent on purpose. `notification` is what the system tray
     * renders without waking the app, and `data` is what the app reads to decide
     * where a tap should go. Sending only `notification` would deliver a banner
     * that opens the launcher; sending only `data` would deliver nothing at all
     * while the app is dead, because FCM treats a data-only message as
     * lower-priority.
     */
    private function messageFor(string $token, PushPayload $payload): array
    {
        $androidNotification = [
            'channel_id' => (string) config('services.push.fcm.channel_id', 'bookalook_notifications'),
        ];

        if ($payload->action !== null) {
            $androidNotification['click_action'] = 'FLUTTER_NOTIFICATION_CLICK';
        }

        $message = [
            'token' => $token,
            'notification' => $payload->toNotificationArray(),
            'data' => $payload->toDataArray(),
            'android' => [
                'priority' => 'high',
                'notification' => $androidNotification,
            ],
        ];

        if ($payload->imageUrl !== null && $payload->imageUrl !== '') {
            $message['android']['notification']['image'] = $payload->imageUrl;
        }

        return $message;
    }

    /**
     * Refuse a message FCM would reject anyway, naming the field that caused it.
     *
     * Throws rather than returning a per-device failure, because the verdict is
     * the same for every device and retrying cannot change it: the queue retry
     * that this triggers is for transport problems, and this is not one. A loud
     * failure here is the difference between "our notification text is too long"
     * and "every phone in the country got an error", which is what the provider
     * would otherwise report.
     */
    private function assertWithinSizeLimit(PushPayload $payload): void
    {
        $size = $payload->byteSize();

        if ($size <= self::MAX_MESSAGE_BYTES) {
            return;
        }

        throw new RuntimeException(sprintf(
            'The push for notification %s is %d bytes, over FCM\'s %d byte limit. '
            .'Shorten the title/message or the data payload before sending.',
            $payload->notificationId,
            $size,
            self::MAX_MESSAGE_BYTES
        ));
    }

    /**
     * Turn FCM's answer into a delivery verdict.
     */
    private function interpret(Response $response, UserDevice $device, PushPayload $payload): PushResult
    {
        $status = $response->status();
        $reason = $this->reasonFrom($response, $device->push_token);

        // A revoked or rotated key. Drop the token and let the gateway-wide
        // failure below throw, so the queue retries with a fresh assertion.
        if ($status === 401) {
            $this->tokens->forget();

            throw new RuntimeException(
                'Firebase rejected our access token (401). The service account may have been revoked. '.$reason
            );
        }

        // The service account is not allowed to send. Retrying will not help, but
        // failing loudly is the point: silently skipping would make a
        // misconfigured server look like a quiet week.
        if ($status === 403) {
            throw new RuntimeException(
                'Firebase refused the send (403). Check that the service account has the '
                .'"Firebase Cloud Messaging Sender" role. '.$reason
            );
        }

        if ($this->isDeadToken($response, $reason)) {
            Log::info('Firebase no longer recognises a device token; signing it off', [
                'notification_id' => $payload->notificationId,
                'device_id' => $device->id,
                'user_id' => $device->user_id,
                'device_token' => $device->maskedToken(),
                'status' => $status,
            ]);

            return PushResult::failed(self::PROVIDER, $reason, deactivateDevice: true);
        }

        // Rate limited or FCM is unwell. Nothing is wrong with this token, so it
        // stays active and the delivery stays pending rather than failed.
        if ($status === 429 || $status >= 500) {
            Log::warning('Firebase could not take a push right now; leaving it pending', [
                'notification_id' => $payload->notificationId,
                'device_id' => $device->id,
                'status' => $status,
            ]);

            return PushResult::failed(self::PROVIDER, $reason, deactivateDevice: false, retryable: true);
        }

        // Anything else 4xx is a bad request — an over-long title, say. That is
        // our fault and will recur, but it is not the device's fault, so the
        // device keeps its registration.
        return PushResult::failed(self::PROVIDER, $reason, deactivateDevice: false, retryable: false);
    }

    /**
     * FCM signals an unregistered token two ways, and both mean the same thing.
     *
     * The 404 NOT_FOUND is unambiguous. The 400 is not: FCM also returns 400 for
     * a malformed message. The message body is what separates "your token is
     * dead" from "your payload is wrong", so the body is inspected — and only
     * the fragments FCM actually uses are matched, rather than any 400 being
     * treated as a dead token and quietly signing working phones off.
     *
     * Takes the already-redacted reason rather than re-reading the response, so
     * the text matched against is exactly the text that will be stored.
     */
    private function isDeadToken(Response $response, string $reason): bool
    {
        if ($response->status() === 404) {
            return true;
        }

        if ($response->status() !== 400) {
            return false;
        }

        $haystack = mb_strtolower($reason);

        foreach ([
            'registration-token-not-registered',
            'requested entity was not found',
            'invalid registration token',
            'token is not valid',
        ] as $fragment) {
            if (str_contains($haystack, $fragment)) {
                return true;
            }
        }

        return false;
    }

    /**
     * A message safe to store in the ledger and to log.
     *
     * FCM's own error strings are short and contain no customer data, but a
     * malformed-token complaint quotes the token back, and that string gets
     * written to notification_deliveries and to the log. So the token this send
     * actually used is removed by value — not guessed at — before either happens.
     *
     * The length-based sweep behind it is the backstop, for a provider that
     * echoes some *other* token-shaped string. The threshold is low (40) because
     * a real FCM registration token is written as two colon-separated halves,
     * each of which is comfortably shorter than 80; measuring the whole token
     * would miss exactly the case this exists for.
     */
    private function reasonFrom(Response $response, ?string $sentToken = null): string
    {
        $message = $response->json('error.message')
            ?? $response->json('message')
            ?: 'Firebase returned HTTP '.$response->status().'.';

        $message = (string) $message;

        if ($sentToken !== null && $sentToken !== '') {
            $message = str_replace($sentToken, '[redacted-token]', $message);
        }

        // Cap the stored reason: a provider that starts returning a stack trace
        // should not be able to fill the ledger with it.
        return mb_substr((string) preg_replace('/[A-Za-z0-9_\-]{40,}/', '[redacted-token]', $message), 0, 500);
    }

    private function endpoint(): string
    {
        return sprintf(
            'https://fcm.googleapis.com/v1/projects/%s/messages:send',
            $this->credentials->projectId
        );
    }
}
