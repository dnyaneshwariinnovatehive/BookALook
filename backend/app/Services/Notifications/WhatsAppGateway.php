<?php

namespace App\Services\Notifications;

use App\Models\WhatsAppMessage;

/**
 * The seam a real WhatsApp Business provider (Meta Cloud API, Twilio, Gupshup)
 * plugs into.
 *
 * Implementations receive an already-persisted [WhatsAppMessage] row and are
 * responsible for marking it sent or failed, so delivery state always lives in
 * the outbox rather than in the provider SDK.
 */
interface WhatsAppGateway
{
    /**
     * Attempt delivery. Must not throw for ordinary provider failures — record
     * them on the message instead, so one bad number cannot abort a mass
     * notification run.
     */
    public function send(WhatsAppMessage $message): void;
}
