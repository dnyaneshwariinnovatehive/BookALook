<?php

namespace App\Services\Notifications;

/**
 * What one device did with one push.
 *
 * A gateway gets many devices and gets to say something different about each of
 * them — that is the whole point of a fan-out send, and a gateway that can only
 * return "done" throws away the information the delivery ledger exists to keep.
 *
 * `deactivateDevice` is the one field that reaches back into our data rather
 * than just reporting. FCM answers an unregistered token with a success-shaped
 * error, and a gateway that swallowed that would leave the app pushing into a
 * void forever. A gateway that knows, it says so here, and the job signs the
 * device off instead of guessing.
 */
final class PushResult
{
    public function __construct(
        public readonly bool $accepted,
        public readonly string $provider,
        public readonly ?string $messageId = null,
        public readonly ?string $failureReason = null,
        public readonly bool $deactivateDevice = false,
    ) {
    }

    public static function accepted(string $provider, ?string $messageId = null): self
    {
        return new self(
            accepted: true,
            provider: $provider,
            messageId: $messageId,
        );
    }

    public static function failed(string $provider, string $failureReason, bool $deactivateDevice = false): self
    {
        return new self(
            accepted: false,
            provider: $provider,
            failureReason: $failureReason,
            deactivateDevice: $deactivateDevice,
        );
    }
}
