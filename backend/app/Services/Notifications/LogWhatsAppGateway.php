<?php

namespace App\Services\Notifications;

use App\Models\WhatsAppMessage;
use Illuminate\Support\Facades\Log;

/**
 * Default gateway until a WhatsApp Business account is connected.
 *
 * It deliberately does NOT mark messages as sent — they stay `queued` so that
 * when a real provider is wired in it can drain the backlog, and so nobody
 * mistakes a logged line for a delivered message.
 */
class LogWhatsAppGateway implements WhatsAppGateway
{
    public function send(WhatsAppMessage $message): void
    {
        Log::info('WhatsApp message queued (no provider configured)', [
            'message_id' => $message->id,
            'to' => $message->to_phone,
            'template' => $message->template,
            'payload' => $message->payload,
        ]);

        $message->forceFill([
            'provider' => 'log',
            'status' => WhatsAppMessage::STATUS_QUEUED,
        ])->save();
    }
}
