<?php

namespace App\Services\Notifications;

use App\Support\Notifications\NotificationAction;

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
        public readonly ?string $imageUrl = null,
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
            action: $notification->action,
            appointmentId: $notification->related_appointment_id,
            salonId: $notification->related_salon_id,
            imageUrl: isset($data['image_url']) ? (string) $data['image_url'] : null,
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
        $block = [
            'title' => $this->title,
            'body' => $this->message,
        ];

        if ($this->imageUrl !== null && $this->imageUrl !== '') {
            $block['image'] = $this->imageUrl;
        }

        return $block;
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

        // The generic pair the app's action router reads, so routing is one
        // lookup on `action` rather than a field-name guess per action type.
        // Populated from the action's declared entity, and skipped entirely when
        // the action points at nothing.
        $entityType = $this->entityType();
        $entityId = $this->entityId();

        if ($entityType !== null) {
            $data['entity_type'] = $entityType;
        }

        if ($entityId !== null) {
            $data['entity_id'] = $entityId;
        }

        return $data;
    }

    /**
     * How large this payload is, in bytes, once encoded.
     *
     * Measured here because the rule belongs to the provider but the arithmetic
     * belongs to the payload. Bytes rather than characters, because the limit is
     * in bytes and a message of emoji and Indian names can pass a character count
     * and still be rejected.
     */
    public function byteSize(): int
    {
        return strlen((string) json_encode([
            'notification' => $this->toNotificationArray(),
            'data' => $this->toDataArray(),
        ]));
    }

    public function entityType(): ?string
    {
        return NotificationAction::entityTypeFor($this->action);
    }

    public function entityId(): ?string
    {
        $key = NotificationAction::entityKeyFor($this->action);

        if ($key === null) {
            return null;
        }

        // The explicit top-level property wins over anything sitting in `data`,
        // because it came from a real column rather than from a payload.
        $candidates = [
            'appointment_id' => $this->appointmentId,
            'salon_id' => $this->salonId,
        ];

        if (isset($candidates[$key]) && $candidates[$key] !== null) {
            return (string) $candidates[$key];
        }

        if (isset($this->data[$key]) && $this->data[$key] !== null && $this->data[$key] !== '') {
            return $this->stringify($this->data[$key]);
        }

        return null;
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
