<?php

namespace App\Services\Notifications;

/**
 * Everything a gateway needs to build a push, and nothing that belongs to a
 * particular provider.
 *
 * FCM wants a title and a body in one place and a flat string-to-string map
 * beside it; Kreait models that as its own Message class. Neither of those
 * shapes is allowed to leak through this interface, so the payload is described
 * here in our own terms and each gateway maps it to whatever its provider
 * expects.
 */
final class PushPayload
{
    public function __construct(
        public readonly string $notificationId,
        public readonly string $type,
        public readonly string $title,
        public readonly string $message,
        public readonly array $data = [],
        public readonly ?string $action = null,
        public readonly ?string $appointmentId = null,
        public readonly ?string $salonId = null,
    ) {
    }

    public static function fromNotification(\App\Models\Notification $notification): self
    {
        $data = is_array($notification->data) ? $notification->data : [];

        return new self(
            notificationId: (string) $notification->id,
            type: (string) $notification->type,
            title: (string) $notification->title,
            message: (string) $notification->message,
            data: $data,
            action: isset($data['action']) ? (string) $data['action'] : null,
            appointmentId: $notification->related_appointment_id,
            salonId: $notification->related_salon_id,
        );
    }

    /**
     * The route the app should open when the notification is tapped.
     */
    public function deeplink(): ?string
    {
        return isset($this->data['deeplink']) ? (string) $this->data['deeplink'] : null;
    }

    /**
     * The notification block: what the phone shows while it is locked.
     */
    public function toNotificationArray(): array
    {
        return [
            'title' => $this->title,
            'body' => $this->message,
        ];
    }

    /**
     * The data block: what the app reads once the phone is awake.
     *
     * Every value is a string and nothing nested survives. That is not
     * fastidiousness, it is FCM's own rule — the data map accepts strings only,
     * drops the lot past 4KB, and a nested array is the quiet way to have a
     * notification arrive with its payload silently empty.
     */
    public function toDataArray(): array
    {
        $data = [];

        foreach ($this->data as $key => $value) {
            $data[(string) $key] = $this->stringify($value);
        }

        // Written after the notification's own data so a payload cannot
        // impersonate a different notification.
        $data['notification_id'] = $this->notificationId;
        $data['type'] = $this->type;

        foreach ([
            'action' => $this->action,
            'appointment_id' => $this->appointmentId,
            'salon_id' => $this->salonId,
        ] as $key => $value) {
            if ($value !== null && ! isset($data[$key])) {
                $data[$key] = $value;
            }
        }

        return $data;
    }

    private function stringify(mixed $value): string
    {
        if (is_bool($value)) {
            return $value ? 'true' : 'false';
        }

        if ($value === null) {
            return '';
        }

        if (is_scalar($value)) {
            return (string) $value;
        }

        return (string) json_encode($value);
    }
}
