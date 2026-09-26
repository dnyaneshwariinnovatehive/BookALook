<?php

namespace App\Support\Notifications;

/**
 * What the app should open when a notification is tapped.
 *
 * The action is the contract between the backend and the app's
 * NotificationActionRouter. The backend decides it, the app routes it, and
 * neither side guesses. `reschedule_appointment` is the one that already ships —
 * the Customer App's inbox has honoured it since the in-app notification landed
 * — so it keeps its exact value.
 *
 * A notification whose action is unknown to the app must degrade to "open the
 * inbox", never to a crash and never to a blank screen. That is why every entry
 * here carries the entity it points at, and why the router is a lookup rather
 * than a chain of string comparisons.
 */
final class NotificationAction
{
    /** Open the reschedule screen for an appointment. Pre-existing contract. */
    public const RESCHEDULE_APPOINTMENT = 'reschedule_appointment';

    /** Open one appointment. */
    public const VIEW_APPOINTMENT = 'view_appointment';

    /** Open the payment sheet for a booking awaiting its advance. */
    public const PAY_APPOINTMENT = 'pay_appointment';

    /** Open the rating prompt for a finished visit. */
    public const RATE_APPOINTMENT = 'rate_appointment';

    /** Open the salon a notification is about. */
    public const VIEW_SALON = 'view_salon';

    /** Open the booking list. */
    public const VIEW_BOOKINGS = 'view_bookings';

    /** Nothing to open. The app shows the notification and stops. */
    public const NONE = 'none';

    /**
     * action => [entity type the action needs, entity key in the data payload].
     *
     * The entity key is deliberately explicit rather than assumed. `action` and
     * `entity_type`/`entity_id` arrive as FCM data strings, where everything is
     * a string and nothing is nested, so the router needs to know which key
     * carries the id rather than casting everything to an int and hoping.
     *
     * @var array<string, array{entity_type: string|null, entity_key: string|null}>
     */
    private const DEFINITIONS = [
        self::RESCHEDULE_APPOINTMENT => [
            'entity_type' => 'appointment',
            'entity_key' => 'appointment_id',
        ],
        self::VIEW_APPOINTMENT => [
            'entity_type' => 'appointment',
            'entity_key' => 'appointment_id',
        ],
        self::PAY_APPOINTMENT => [
            'entity_type' => 'appointment',
            'entity_key' => 'appointment_id',
        ],
        self::RATE_APPOINTMENT => [
            'entity_type' => 'appointment',
            'entity_key' => 'appointment_id',
        ],
        self::VIEW_SALON => [
            'entity_type' => 'salon',
            'entity_key' => 'salon_id',
        ],
        self::VIEW_BOOKINGS => [
            'entity_type' => null,
            'entity_key' => null,
        ],
        self::NONE => [
            'entity_type' => null,
            'entity_key' => null,
        ],
    ];

    public static function isKnown(?string $action): bool
    {
        return $action !== null && isset(self::DEFINITIONS[$action]);
    }

    /**
     * @return array{entity_type: string|null, entity_key: string|null}
     */
    public static function definitionFor(?string $action): array
    {
        return self::DEFINITIONS[$action ?? self::NONE] ?? self::DEFINITIONS[self::NONE];
    }

    public static function entityTypeFor(?string $action): ?string
    {
        return self::definitionFor($action)['entity_type'];
    }

    public static function entityKeyFor(?string $action): ?string
    {
        return self::definitionFor($action)['entity_key'];
    }

    /**
     * True when the action can only be honoured if the payload carries its
     * entity. A reschedule tap with no appointment id has nothing to open, and
     * the app is expected to fall back to the inbox rather than push a screen
     * built from a null.
     */
    public static function requiresEntity(?string $action): bool
    {
        return self::entityKeyFor($action) !== null;
    }
}
