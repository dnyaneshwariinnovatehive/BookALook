<?php

namespace App\Services\Notifications;

use App\Jobs\SendPushNotificationJob;
use App\Models\Appointment;
use App\Models\Notification;
use App\Models\Salon;
use App\Models\User;
use App\Models\WhatsAppMessage;
use App\Support\Notifications\NotificationAction;
use App\Support\Notifications\NotificationType;
use Illuminate\Support\Facades\Log;

/**
 * One place to reach a customer.
 *
 * Every notification lands in the in-app inbox first — that is the channel we
 * actually control — and is then mirrored to WhatsApp and to the recipient's
 * registered phones. A failure on either mirror must never cost the customer
 * their in-app notice, so both are wrapped and only logged.
 *
 * Push is queued rather than sent inline because the caller is usually inside
 * a database transaction, and a device lookup plus a provider call in the
 * middle of one would hold a booking open for a network round trip.
 *
 * `send()` is the only way a notification gets written. Business methods below
 * it exist so that the wording of a given event lives with the event, and so
 * that a second call site for the same event cannot invent a second phrasing for
 * it. Anything reaching for `Notification::create()` directly is bypassing this
 * and will not get a push.
 */
class NotificationService
{
    public const TYPE_SALON_CLOSED = NotificationType::SALON_CLOSURE;

    public function __construct(private WhatsAppGateway $whatsapp)
    {
    }

    /**
     * The single entry point. Writes the inbox row and schedules the push.
     *
     * Returns null — not an exception — when there is nobody to notify. A
     * walk-in booking has no customer account, and a cancellation of somebody
     * else's appointment must not be able to take down the controller that
     * happened to trigger it.
     *
     * @param  array<string, mixed>  $data  Structured payload. Stays small: this
     *                                       is what ends up in the FCM data block.
     * @param  string|null  $dedupeKey  Makes the write idempotent. A second
     *                                  attempt with the same key returns null.
     */
    public function send(
        User|string|null $recipient,
        string $type,
        string $title,
        string $message,
        array $data = [],
        ?Appointment $appointment = null,
        ?Salon $salon = null,
        ?string $dedupeKey = null
    ): ?Notification {
        $userId = $recipient instanceof User ? $recipient->id : $recipient;

        if (! $userId) {
            return null;
        }

        // A payload that arrives without an action still routes sensibly: the
        // type knows what it would normally open.
        if (! isset($data['action'])) {
            $default = NotificationType::defaultActionFor($type);

            if ($default !== null) {
                $data['action'] = $default;
            }
        }

        $notification = Notification::createOnce([
            'user_id' => $userId,
            'type' => $type,
            'title' => $title,
            'message' => $message,
            'data' => $data,
            'related_appointment_id' => $appointment?->id,
            'related_salon_id' => $salon?->id ?? $appointment?->salon_id,
            'is_read' => false,
        ], $dedupeKey);

        // A dedupe collision is not a failure — it means this exact notice has
        // already gone out, which is the outcome the caller wanted.
        if (! $notification) {
            return null;
        }

        // Queued from here, rather than from each caller, so a new notification
        // cannot be added without also being pushed.
        $this->mirrorToPush($notification);

        return $notification;
    }

    /*
    |---------------------------------------------------------------------------
    | Customer events
    |---------------------------------------------------------------------------
    */

    /**
     * Tell a customer their booking lost its day and they can move it for free.
     */
    public function appointmentNeedsReschedule(
        Appointment $appointment,
        string $salonName,
        string $dateLabel,
        ?string $reason
    ): ?Notification {
        $because = $reason ? " ({$reason})" : '';

        $notification = $this->send(
            recipient: $appointment->customer_id,
            type: NotificationType::SALON_CLOSURE,
            title: 'Your appointment needs a new time',
            message: "{$salonName} is closed on {$dateLabel}{$because}. "
                . 'Your booking has been released and you can pick a new slot free of charge — '
                . 'the amount you already paid carries over.',
            data: [
                'action' => NotificationAction::RESCHEDULE_APPOINTMENT,
                'appointment_id' => $appointment->id,
                'free_reschedule' => true,
                'deeplink' => $this->rescheduleDeeplink($appointment->id),
            ],
            appointment: $appointment,
        );

        if ($notification) {
            $this->mirrorToWhatsApp($appointment, [
                'salon_name' => $salonName,
                'appointment_date' => $dateLabel,
                'reason' => $reason,
                'reschedule_link' => $this->rescheduleDeeplink($appointment->id),
            ]);
        }

        return $notification;
    }

    /**
     * The booking exists but the advance has not landed yet.
     *
     * Worth a push on its own: without it the customer's only sign the booking
     * took is a screen they have to remember to go back to.
     */
    public function bookingAwaitingPayment(Appointment $appointment, string $salonName, float $advanceDue): ?Notification
    {
        return $this->send(
            recipient: $appointment->customer_id,
            type: NotificationType::BOOKING_CREATED,
            title: 'Booking created — complete the payment',
            message: "Your booking at {$salonName} is held. Pay ".config('app.currency_symbol', '₹')
                .number_format($advanceDue, 2).' to confirm it.',
            data: [
                'action' => NotificationAction::PAY_APPOINTMENT,
                'appointment_id' => $appointment->id,
                'advance_due' => $advanceDue,
                'deeplink' => $this->appointmentDeeplink($appointment->id),
            ],
            appointment: $appointment,
        );
    }

    /**
     * The advance cleared, so the salon has a confirmed booking.
     */
    public function bookingConfirmed(Appointment $appointment, string $salonName, string $dateLabel): ?Notification
    {
        return $this->send(
            recipient: $appointment->customer_id,
            type: NotificationType::BOOKING_CONFIRMED,
            title: 'Booking confirmed',
            message: "Your booking at {$salonName} on {$dateLabel} is confirmed.",
            data: [
                'action' => NotificationAction::VIEW_APPOINTMENT,
                'appointment_id' => $appointment->id,
                'deeplink' => $this->appointmentDeeplink($appointment->id),
            ],
            appointment: $appointment,
        );
    }

    /**
     * The customer cancelled their own appointment.
     */
    public function bookingCancelled(Appointment $appointment, string $salonName, string $dateLabel): ?Notification
    {
        return $this->send(
            recipient: $appointment->customer_id,
            type: NotificationType::BOOKING_CANCELLED,
            title: 'Booking cancelled',
            message: "Your booking at {$salonName} on {$dateLabel} has been cancelled.",
            data: [
                'action' => NotificationAction::VIEW_APPOINTMENT,
                'appointment_id' => $appointment->id,
                'deeplink' => $this->appointmentDeeplink($appointment->id),
            ],
            appointment: $appointment,
        );
    }

    /**
     * The customer moved their own appointment. The counterpart to the salon
     * closing a day: the booking still stands, at a new time.
     */
    public function bookingRescheduled(Appointment $appointment, string $salonName, string $dateLabel): ?Notification
    {
        return $this->send(
            recipient: $appointment->customer_id,
            type: NotificationType::BOOKING_RESCHEDULED,
            title: 'Booking rescheduled',
            message: "Your booking at {$salonName} has moved to {$dateLabel}.",
            data: [
                'action' => NotificationAction::VIEW_APPOINTMENT,
                'appointment_id' => $appointment->id,
                'deeplink' => $this->appointmentDeeplink($appointment->id),
            ],
            appointment: $appointment,
        );
    }

    /**
     * A reminder ahead of an appointment.
     *
     * Idempotent by construction: the caller passes a dedupe key built from the
     * appointment and the reminder window, so a scheduler that runs twice, or
     * two workers that race, still produce exactly one reminder.
     */
    public function appointmentReminder(
        Appointment $appointment,
        string $salonName,
        string $dateLabel,
        string $dedupeKey
    ): ?Notification {
        return $this->send(
            recipient: $appointment->customer_id,
            type: NotificationType::APPOINTMENT_REMINDER,
            title: 'Reminder: your appointment is coming up',
            message: "You are booked at {$salonName} on {$dateLabel}.",
            data: [
                'action' => NotificationAction::VIEW_APPOINTMENT,
                'appointment_id' => $appointment->id,
                'deeplink' => $this->appointmentDeeplink($appointment->id),
            ],
            appointment: $appointment,
            dedupeKey: $dedupeKey,
        );
    }

    /**
     * An appointment passed its window untouched and was swept to no-show.
     *
     * Idempotent, because the sweep is a scheduled command and a day where it
     * runs twice must not tell a customer they missed two visits.
     */
    public function appointmentMarkedNoShow(Appointment $appointment, string $salonName, ?string $dedupeKey = null): ?Notification
    {
        return $this->send(
            recipient: $appointment->customer_id,
            type: NotificationType::APPOINTMENT_NO_SHOW,
            title: 'Your appointment was missed',
            message: "The booking at {$salonName} was marked as missed because nobody checked in.",
            data: [
                'action' => NotificationAction::VIEW_APPOINTMENT,
                'appointment_id' => $appointment->id,
                'deeplink' => $this->appointmentDeeplink($appointment->id),
            ],
            appointment: $appointment,
            dedupeKey: $dedupeKey,
        );
    }

    /**
     * The salon finished the appointment. The prompt for a rating follows.
     *
     * Takes a dedupe key because "collect payment and complete" is reachable
     * twice for one visit: a provider taps it, the network drops, they tap again.
     * Without the key the customer is asked to rate the same visit twice, which
     * reads as a bug in the salon rather than in the network.
     */
    public function appointmentCompleted(Appointment $appointment, string $salonName, ?string $dedupeKey = null): ?Notification
    {
        return $this->send(
            recipient: $appointment->customer_id,
            type: NotificationType::APPOINTMENT_COMPLETED,
            title: 'How was your visit?',
            message: "Your appointment at {$salonName} is complete. Rate your experience.",
            data: [
                'action' => NotificationAction::RATE_APPOINTMENT,
                'appointment_id' => $appointment->id,
                'deeplink' => $this->appointmentDeeplink($appointment->id),
            ],
            appointment: $appointment,
            dedupeKey: $dedupeKey,
        );
    }

    /*
    |---------------------------------------------------------------------------
    | Partner events
    |---------------------------------------------------------------------------
    */

    /**
     * Alert a service provider that a customer rescheduled their appointment,
     * freeing up this slot.
     */
    public function providerAppointmentRescheduled(Appointment $appointment): ?Notification
    {
        $provider = $appointment->appointedProvider;

        if (! $provider || ! $provider->user_id) {
            return null;
        }

        $customerName = $appointment->customer?->name ?? $appointment->walk_in_customer_name;
        $dateLabel = $this->dateTimeLabel($appointment);

        return $this->send(
            recipient: $provider->user_id,
            type: NotificationType::PROVIDER_APPOINTMENT_RESCHEDULED,
            title: 'Appointment Rescheduled',
            message: "Your appointment with {$customerName} on {$dateLabel} has been rescheduled by the customer.",
            data: [
                'action' => NotificationAction::VIEW_APPOINTMENT,
                'appointment_id' => $appointment->id,
            ],
            appointment: $appointment,
        );
    }

    /**
     * A customer booked with this salon. Addressed to the provider who will
     * serve it where one was chosen, and to the salon owner otherwise — the
     * person who would otherwise find out by opening the app.
     */
    public function notifySalonOfNewBooking(Appointment $appointment, string $salonName, string $dateLabel): void
    {
        $recipients = [];

        $providerId = $appointment->appointedProvider?->user_id;

        if ($providerId) {
            $recipients[] = $providerId;
        }

        $adminId = $appointment->salon?->admin_id;

        if ($adminId && ! in_array($adminId, $recipients, true)) {
            $recipients[] = $adminId;
        }

        $customerName = $appointment->customer?->name ?? $appointment->walk_in_customer_name;

        foreach (array_unique($recipients) as $recipientId) {
            $this->send(
                recipient: $recipientId,
                type: NotificationType::NEW_BOOKING,
                title: 'New booking',
                message: "{$customerName} booked {$dateLabel} at {$salonName}.",
                data: [
                    'action' => NotificationAction::VIEW_APPOINTMENT,
                    'appointment_id' => $appointment->id,
                ],
                appointment: $appointment,
            );
        }
    }

    /*
    |---------------------------------------------------------------------------
    | Mirrors
    |---------------------------------------------------------------------------
    */

    /**
     * Queue the push mirror. Never throws: a notification run for a whole day of
     * bookings must not stop because one device could not be registered.
     *
     * afterCommit() is stated at the call site as well as being the job's own
     * default, because the order is load-bearing. SalonClosureService wraps
     * itself in DB::transaction() and the customer's reschedule commits several
     * lines after this returns; a worker that picked the job up in between
     * would go looking for a notification row that is not committed yet, and
     * quietly decide there is nothing to send.
     */
    private function mirrorToPush(Notification $notification): void
    {
        try {
            SendPushNotificationJob::dispatch($notification->id)->afterCommit();
        } catch (\Throwable $e) {
            Log::warning('Could not queue push notification', [
                'notification_id' => $notification->id,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Queue the WhatsApp mirror. Never throws: a notification run for a whole
     * day of bookings must not stop because one row failed.
     */
    private function mirrorToWhatsApp(Appointment $appointment, array $payload): void
    {
        try {
            $phone = $this->phoneFor($appointment);

            if (! $phone) {
                return;
            }

            $message = WhatsAppMessage::create([
                'user_id' => $appointment->customer_id,
                'to_phone' => $phone,
                'template' => config('services.whatsapp.templates.salon_closure', 'salon_closure_reschedule'),
                'payload' => $payload,
                'related_appointment_id' => $appointment->id,
                'related_salon_id' => $appointment->salon_id,
                'status' => WhatsAppMessage::STATUS_QUEUED,
            ]);

            $this->whatsapp->send($message);
        } catch (\Throwable $e) {
            Log::warning('Could not queue WhatsApp notification', [
                'appointment_id' => $appointment->id,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /*
    |---------------------------------------------------------------------------
    | Helpers
    |---------------------------------------------------------------------------
    */

    private function phoneFor(Appointment $appointment): ?string
    {
        if ($appointment->customer_id) {
            $phone = User::whereKey($appointment->customer_id)->value('phone');

            if ($phone) {
                return $phone;
            }
        }

        return $appointment->walk_in_customer_phone;
    }

    /**
     * The "free reschedule link" a customer taps from WhatsApp or the inbox.
     */
    private function rescheduleDeeplink(string $appointmentId): string
    {
        return $this->deeplink('appointments/'.$appointmentId.'/reschedule');
    }

    private function appointmentDeeplink(string $appointmentId): string
    {
        return $this->deeplink('appointments/'.$appointmentId);
    }

    private function deeplink(string $path): string
    {
        $base = rtrim((string) config('services.customer_app.deeplink_base'), '/');

        return $base.'/'.$path;
    }

    /**
     * "Sep 26, 2026 at 4:30 PM", in one place, because six of the messages
     * above need it and a customer reading two of them in a week should not see
     * two different formats.
     */
    private function dateTimeLabel(Appointment $appointment): string
    {
        return \Carbon\Carbon::parse($appointment->appointment_date)->format('M d, Y')
            .' at '
            .\Carbon\Carbon::parse($appointment->start_time)->format('h:i A');
    }
}
