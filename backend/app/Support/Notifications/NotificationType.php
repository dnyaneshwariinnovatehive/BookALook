<?php

namespace App\Support\Notifications;

/**
 * The vocabulary every notification in the system is written in.
 *
 * Types were previously string literals scattered across the controllers that
 * happened to send them, which meant the set of things a customer can be told
 * could only be discovered by reading the codebase. This is that set, in one
 * place, with the two facts the delivery pipeline needs to know about each entry
 * spelled out: whether it is something the customer must never miss, and what
 * the app should open when they tap it.
 *
 * The string values are the contract. They are already stored in the
 * `notifications.type` column on production and are matched by the two Flutter
 * apps, so they are frozen — adding to this list is safe, renaming anything is
 * not.
 */
final class NotificationType
{
    /*
    |---------------------------------------------------------------------------
    | Customer
    |---------------------------------------------------------------------------
    */

    /** A salon shut a trading day; the booking was released. */
    public const SALON_CLOSURE = 'salon_closure';

    /** The customer placed a booking and owes the advance. */
    public const BOOKING_CREATED = 'booking_created';

    /** The advance was paid, so the salon now has a confirmed booking. */
    public const BOOKING_CONFIRMED = 'booking_confirmed';

    /** The customer cancelled their own appointment. */
    public const BOOKING_CANCELLED = 'booking_cancelled';

    /** The customer moved their own appointment to a new time. */
    public const BOOKING_RESCHEDULED = 'booking_rescheduled';

    /** Somewhere ahead of an appointment it is time to remember it exists. */
    public const APPOINTMENT_REMINDER = 'appointment_reminder';

    /** An appointment passed its window untouched and was swept to no-show. */
    public const APPOINTMENT_NO_SHOW = 'appointment_no_show';

    /** The salon finished the appointment. */
    public const APPOINTMENT_COMPLETED = 'appointment_completed';

    /*
    |---------------------------------------------------------------------------
    | Partner / salon
    |---------------------------------------------------------------------------
    */

    /** A customer booked with this salon. */
    public const NEW_BOOKING = 'new_booking';

    /** A customer rescheduled, freeing the slot they had. */
    public const PROVIDER_APPOINTMENT_RESCHEDULED = 'appointment_rescheduled';

    /** SuperAdmin raised a complaint about the salon. */
    public const COMPLAINT_RAISED = 'complaint_raised';

    /** SuperAdmin warned the salon about a complaint. */
    public const COMPLAINT_WARNING = 'complaint_warning';

    /** SuperAdmin suspended the salon. */
    public const SALON_SUSPENDED = 'salon_suspended';

    /** SuperAdmin put the salon back online. */
    public const SALON_REINSTATED = 'salon_reinstated';

    /** A plan is about to lapse. */
    public const SUBSCRIPTION_EXPIRING = 'subscription_expiring';

    /** A plan has lapsed. */
    public const SUBSCRIPTION_EXPIRED = 'subscription_expired';

    /** A salon this collaborator onboards is about to lapse. */
    public const ASSIGNED_SALON_EXPIRING = 'assigned_salon_expiring';

    /*
    |---------------------------------------------------------------------------
    | Fallback
    |---------------------------------------------------------------------------
    */

    /**
     * The catch-all the provider audience already receives.
     *
     * `providerAppointmentRescheduled()` shipped with this value hardcoded and a
     * comment admitting it was a placeholder. It stays registered so historical
     * rows and anything still writing it keep rendering, but new code should
     * name the event instead.
     */
    public const GENERAL = 'general';

    /*
    |---------------------------------------------------------------------------
    | Categories
    |---------------------------------------------------------------------------
    */

    /**
     * Something the account depends on: a booking moved, a payment landed, a
     * salon was suspended. Never suppressed by a user preference.
     */
    public const CATEGORY_TRANSACTIONAL = 'transactional';

    /**
     * Something the platform chose to send. A user may switch these off and
     * nothing is lost that they were relying on.
     */
    public const CATEGORY_PROMOTIONAL = 'promotional';

    /**
     * Operational notices about the account itself, aimed at staff rather than
     * customers. Treated as transactional: a lapsed plan is not an advert.
     */
    public const CATEGORY_SYSTEM = 'system';

    /**
     * type => [category, default action, human label].
     *
     * The label is not decoration — it is what the app shows in a grouped inbox
     * and what the log says when a push fails, so "unknown notification type" is
     * never a thing anybody has to read.
     *
     * @var array<string, array{category: string, action: string|null, label: string}>
     */
    private const DEFINITIONS = [
        self::SALON_CLOSURE => [
            'category' => self::CATEGORY_TRANSACTIONAL,
            'action' => NotificationAction::RESCHEDULE_APPOINTMENT,
            'label' => 'Appointment moved',
        ],
        self::BOOKING_CREATED => [
            'category' => self::CATEGORY_TRANSACTIONAL,
            'action' => NotificationAction::PAY_APPOINTMENT,
            'label' => 'Booking awaiting payment',
        ],
        self::BOOKING_CONFIRMED => [
            'category' => self::CATEGORY_TRANSACTIONAL,
            'action' => NotificationAction::VIEW_APPOINTMENT,
            'label' => 'Booking confirmed',
        ],
        self::BOOKING_CANCELLED => [
            'category' => self::CATEGORY_TRANSACTIONAL,
            'action' => NotificationAction::VIEW_APPOINTMENT,
            'label' => 'Booking cancelled',
        ],
        self::BOOKING_RESCHEDULED => [
            'category' => self::CATEGORY_TRANSACTIONAL,
            'action' => NotificationAction::VIEW_APPOINTMENT,
            'label' => 'Booking rescheduled',
        ],
        self::APPOINTMENT_REMINDER => [
            'category' => self::CATEGORY_TRANSACTIONAL,
            'action' => NotificationAction::VIEW_APPOINTMENT,
            'label' => 'Appointment reminder',
        ],
        self::APPOINTMENT_NO_SHOW => [
            'category' => self::CATEGORY_TRANSACTIONAL,
            'action' => NotificationAction::VIEW_APPOINTMENT,
            'label' => 'Marked as missed',
        ],
        self::APPOINTMENT_COMPLETED => [
            'category' => self::CATEGORY_TRANSACTIONAL,
            'action' => NotificationAction::RATE_APPOINTMENT,
            'label' => 'Appointment completed',
        ],

        self::NEW_BOOKING => [
            'category' => self::CATEGORY_TRANSACTIONAL,
            'action' => NotificationAction::VIEW_APPOINTMENT,
            'label' => 'New booking',
        ],
        self::PROVIDER_APPOINTMENT_RESCHEDULED => [
            'category' => self::CATEGORY_TRANSACTIONAL,
            'action' => NotificationAction::VIEW_APPOINTMENT,
            'label' => 'Customer rescheduled',
        ],
        self::COMPLAINT_RAISED => [
            'category' => self::CATEGORY_SYSTEM,
            'action' => null,
            'label' => 'Complaint raised',
        ],
        self::COMPLAINT_WARNING => [
            'category' => self::CATEGORY_SYSTEM,
            'action' => null,
            'label' => 'Platform warning',
        ],
        self::SALON_SUSPENDED => [
            'category' => self::CATEGORY_SYSTEM,
            'action' => null,
            'label' => 'Salon suspended',
        ],
        self::SALON_REINSTATED => [
            'category' => self::CATEGORY_SYSTEM,
            'action' => null,
            'label' => 'Salon back online',
        ],
        self::SUBSCRIPTION_EXPIRING => [
            'category' => self::CATEGORY_SYSTEM,
            'action' => null,
            'label' => 'Plan ending soon',
        ],
        self::SUBSCRIPTION_EXPIRED => [
            'category' => self::CATEGORY_SYSTEM,
            'action' => null,
            'label' => 'Plan expired',
        ],
        self::ASSIGNED_SALON_EXPIRING => [
            'category' => self::CATEGORY_SYSTEM,
            'action' => null,
            'label' => 'Onboarded salon ending soon',
        ],

        self::GENERAL => [
            'category' => self::CATEGORY_TRANSACTIONAL,
            'action' => null,
            'label' => 'Notice',
        ],
    ];

    /**
     * Types that existed before this list did, mapped to the definition that
     * describes them today. Kept so a row written by an older deploy still
     * resolves to a category, a label and a tap target rather than falling
     * through to the generic fallback.
     */
    private const ALIASES = [
        'cancellation' => self::BOOKING_CANCELLED,
        'reschedule' => self::BOOKING_RESCHEDULED,
    ];

    public static function all(): array
    {
        return array_keys(self::DEFINITIONS);
    }

    public static function isKnown(string $type): bool
    {
        return isset(self::DEFINITIONS[self::resolve($type)]);
    }

    /**
     * Fold an alias onto the type that replaced it.
     */
    public static function resolve(string $type): string
    {
        return self::ALIASES[$type] ?? $type;
    }

    /**
     * Unknown types are treated as transactional on purpose. A notification the
     * system has never heard of is far more likely to be something a customer
     * needs than something they opted out of, and defaulting the other way would
     * mean a new event silently never reaches anybody.
     */
    public static function categoryOf(string $type): string
    {
        return self::DEFINITIONS[self::resolve($type)]['category']
            ?? self::CATEGORY_TRANSACTIONAL;
    }

    public static function isPromotional(string $type): bool
    {
        return self::categoryOf($type) === self::CATEGORY_PROMOTIONAL;
    }

    public static function isTransactional(string $type): bool
    {
        return self::categoryOf($type) === self::CATEGORY_TRANSACTIONAL;
    }

    public static function defaultActionFor(string $type): ?string
    {
        return self::DEFINITIONS[self::resolve($type)]['action'] ?? null;
    }

    public static function labelFor(string $type): string
    {
        return self::DEFINITIONS[self::resolve($type)]['label'] ?? 'Notice';
    }

    /**
     * Every type that can be switched on and off by the user, grouped by the
     * preference column that governs it. Promotional only, by construction — a
     * transactional type has nothing to toggle because it is never optional.
     *
     * @return array<string, array<int, string>>
     */
    public static function typesByPreferenceChannel(): array
    {
        $groups = [];

        foreach (self::DEFINITIONS as $type => $definition) {
            if ($definition['category'] === self::CATEGORY_PROMOTIONAL) {
                $groups[$type] = $definition;
            }
        }

        return $groups;
    }

    /**
     * The preference column a type obeys, or null when it is not optional.
     */
    public static function preferenceChannelFor(string $type): ?string
    {
        return self::isPromotional($type) ? 'promotional_notifications' : null;
    }

    /**
     * Which app the recipient is reading when they get this.
     *
     * A salon owner is very often also a customer, with a phone that has both
     * apps installed and a row in `user_devices` for each. Pushing a "your salon
     * is closed" notice to the Partner App install would be wrong, and so would
     * pushing a "somebody booked you" notice to the Customer App one.
     *
     * null means "we do not know, so address every device this user has" — the
     * honest default for a type nobody has classified yet, and the reason an
     * unrecognised type can still reach somebody.
     */
    public static function audienceAppFor(string $type): ?string
    {
        return match (self::resolve($type)) {
            self::SALON_CLOSURE,
            self::BOOKING_CREATED,
            self::BOOKING_CONFIRMED,
            self::BOOKING_CANCELLED,
            self::BOOKING_RESCHEDULED,
            self::APPOINTMENT_REMINDER,
            self::APPOINTMENT_NO_SHOW,
            self::APPOINTMENT_COMPLETED => 'customer_app',

            self::NEW_BOOKING,
            self::PROVIDER_APPOINTMENT_RESCHEDULED,
            self::COMPLAINT_RAISED,
            self::COMPLAINT_WARNING,
            self::SALON_SUSPENDED,
            self::SALON_REINSTATED,
            self::SUBSCRIPTION_EXPIRING,
            self::SUBSCRIPTION_EXPIRED,
            self::ASSIGNED_SALON_EXPIRING => 'partner_app',

            // `general` is only ever written by the provider reschedule path.
            self::GENERAL => 'partner_app',

            default => null,
        };
    }
}
