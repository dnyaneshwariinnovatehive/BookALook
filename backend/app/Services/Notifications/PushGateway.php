<?php

namespace App\Services\Notifications;

use App\Models\UserDevice;

/**
 * Sends one push to many devices and reports on each of them.
 *
 * A send is many-to-one, never one-to-one: the title, body and data are built
 * once and every active device of the recipient is addressed with the same
 * payload. Modelling it that way from the start means the FCM implementation
 * arrives as a loop over `sendMulticast`, with no reshuffling of the callers
 * that built against this shape.
 *
 * Implementations must not depend on the notification, the user, or the
 * database. They receive devices and a payload, and they return a result per
 * device keyed by device id. That is what keeps Firebase's own types on the
 * far side of this interface.
 */
interface PushGateway
{
    /**
     * @param  iterable<UserDevice>  $devices  Active devices holding a token.
     * @return array<string, PushResult>  Keyed by UserDevice id.
     */
    public function send(iterable $devices, PushPayload $payload): array;
}
