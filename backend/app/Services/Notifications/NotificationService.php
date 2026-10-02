<?php

namespace App\Services\Notifications;

use App\Jobs\SendPushNotificationJob;
use App\Jobs\SendWhatsAppMessageJob;
use App\Models\Appointment;
use App\Models\Notification;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\User;
use App\Models\WhatsAppMessage;
use App\Support\Notifications\NotificationAction;
use App\Support\Notifications\NotificationType;
use Carbon\Carbon;
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

    /**
     * Names the attachment a WhatsApp message wants resolved to a real file.
     *
     * Written into the payload rather than a URL, because the document is not
     * rendered when the booking happens — the queued job does it, by which time
     * the invoice exists and the caller is no longer on the request path.
     */
    public const ATTACHMENT_INVOICE = 'invoice';

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
            // Positional, like every other mirror here, because that is the only
            // shape either gateway reads — both build their request body from
            // `parameters`. This one was written as named keys, so it went out
            // with an empty body and every placeholder in the approved template
            // rendered blank.
            //
            // The reason is the last placeholder with actual content rather than
            // the fourth: a closure with no stated reason should read as a closure,
            // not as a message with a hole in it.
            $this->mirrorToWhatsApp($appointment, [
                'parameters' => [
                    $salonName,
                    $dateLabel,
                    $reason ?: 'The salon is closed',
                    $this->rescheduleDeeplink($appointment->id),
                ],
            ], 'salon_closure');
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
     *
     * The only event that carries an attachment: the invoice PDF. It is named by
     * event rather than resolved here because this is called a moment before the
     * invoice is issued, and the PDF is rendered by the queued job anyway — by then
     * both exist, and neither the request nor this method has to wait on a
     * document render.
     */
    public function bookingConfirmed(Appointment $appointment, string $salonName, string $dateLabel): ?Notification
    {
        $notification = $this->send(
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

        if ($notification) {
            $this->mirrorToWhatsApp($appointment, [
                'parameters' => [
                    $salonName,
                    $dateLabel,
                    $this->currency($appointment->advance_amount ?? 0),
                ],
                'attachment' => self::ATTACHMENT_INVOICE,
            ], 'booking_confirmed');
        }

        return $notification;
    }

    /**
     * The customer cancelled their own appointment.
     */
    public function bookingCancelled(Appointment $appointment, string $salonName, string $dateLabel): ?Notification
    {
        $notification = $this->send(
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

        if ($notification) {
            $this->mirrorToWhatsApp($appointment, [
                'parameters' => [
                    $salonName,
                    $dateLabel,
                    $appointment->cancellation_reason ?: 'No reason given',
                ],
            ], 'appointment_cancelled');
        }

        return $notification;
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
     *
     * The WhatsApp mirror hangs off the returned notification rather than firing
     * unconditionally, so it inherits the same dedupe key. A scheduler running
     * four times inside the reminder window produces one message on WhatsApp for
     * the same reason it produces one push.
     */
    public function appointmentReminder(
        Appointment $appointment,
        string $salonName,
        string $dateLabel,
        string $dedupeKey
    ): ?Notification {
        $notification = $this->send(
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

        if ($notification) {
            $this->mirrorToWhatsApp($appointment, [
                'parameters' => [
                    $salonName,
                    $dateLabel,
                    // A salon with no address on file is allowed, and `address` is
                    // a nullable column. Sending the null through would have
                    // AISensy reject the whole message on parameter count and
                    // type, and would put the literal word "null" in the address
                    // slot for Meta — so the placeholder is given something that
                    // reads as an answer rather than a gap.
                    $appointment->salon?->address ?: 'Address in the app',
                ],
            ], 'appointment_reminder');
        }

        return $notification;
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
    | Collaborator events
    |---------------------------------------------------------------------------
    */

    /**
     * A salon in this collaborator's care is about to stop taking bookings.
     *
     * The collaborator cannot pay for somebody else's salon, so there is no
     * renewal action to offer — only the owner's number. The dedupe key is
     * passed in rather than derived here because only the caller knows which
     * warning window this notice belongs to, and the ladder is the caller's
     * business, not the wording's.
     *
     * [$daysLeft] is days until the plan ends, negative once it has. The two
     * sides read as different events because they are: one asks for a call to
     * prevent a lapse, the other reports that the lapse happened and the salon
     * has come off the marketplace.
     *
     * Returns null when the salon has no collaborator, or when this exact
     * window has already been notified. Both are ordinary, not failures.
     */
    public function assignedSalonExpiring(
        Salon $salon,
        int $daysLeft,
        string $dedupeKey
    ): ?Notification {
        $salon->loadMissing('admin:id,name,phone');

        if (! $salon->assigned_collaborator_id) {
            return null;
        }

        $lapsed = $daysLeft < 0;

        if ($lapsed) {
            $title = "{$salon->name}'s plan has expired";
            $message = sprintf(
                '%s is no longer taking bookings. Call %s to get it back online.',
                $salon->name,
                $salon->admin->name ?? 'the owner'
            );
        } else {
            $when = match (true) {
                $daysLeft === 0 => 'today',
                $daysLeft === 1 => 'tomorrow',
                default => "in {$daysLeft} days",
            };

            $title = "{$salon->name}'s plan ends {$when}";
            $message = sprintf(
                'A salon you onboarded is about to stop taking bookings. Give %s a call '
                .'before it goes offline.',
                $salon->admin->name ?? 'the owner'
            );
        }

        return $this->send(
            recipient: $salon->assigned_collaborator_id,
            type: NotificationType::ASSIGNED_SALON_EXPIRING,
            title: $title,
            message: $message,
            data: [
                'action' => NotificationAction::CALL_OWNER,
                'salon_id' => $salon->id,
                'salon_name' => $salon->name,
                'owner_phone' => $salon->admin->phone ?? null,
                'days_left' => $daysLeft,
                'lapsed' => $lapsed,
            ],
            salon: $salon,
            dedupeKey: $dedupeKey,
        );
    }

    /**
     * The owner paid, so the salon this collaborator set up is live again.
     *
     * Fires from every path that puts a paid plan on a salon — the owner's own
     * renew button, buying a different plan, paying in coins, and SuperAdmin
     * approving a transfer — because from the collaborator's side they are one
     * event. Without it the chase they were told to make simply stops, with no
     * confirmation that it worked.
     */
    public function assignedSalonRenewed(
        Salon $salon,
        ?SalonSubscription $subscription = null
    ): ?Notification {
        $salon->loadMissing('admin:id,name');

        if (! $salon->assigned_collaborator_id) {
            return null;
        }

        $plan = $subscription?->plan;
        $planName = $plan?->name ?? 'a plan';

        $message = $subscription?->end_date
            ? sprintf(
                '%s renewed %s. It is live until %s — no call needed.',
                $salon->admin->name ?? 'The owner',
                $planName,
                Carbon::parse($subscription->end_date)->format('j M Y')
            )
            : sprintf('%s renewed %s. No call needed.', $salon->admin->name ?? 'The owner', $planName);

        return $this->send(
            recipient: $salon->assigned_collaborator_id,
            type: NotificationType::ASSIGNED_SALON_RENEWED,
            title: "{$salon->name} is renewed",
            message: $message,
            data: [
                'action' => NotificationAction::VIEW_SALON,
                'salon_id' => $salon->id,
                'salon_name' => $salon->name,
                'plan_name' => $planName,
                'ends_on' => $subscription?->end_date?->toDateString(),
            ],
            salon: $salon,
            // One confirmation per plan period. A salon bought twice on the same
            // day should only be reported once, and a retry after a dropped
            // request must not double it.
            dedupeKey: $subscription
                ? "assigned_salon_renewed:{$salon->id}:{$subscription->id}"
                : null,
        );
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
     *
     * Queued rather than sent inline, for the same reason [mirrorToPush] is — and
     * now also because one of these messages carries an invoice PDF, which means
     * rendering a document and uploading it before the provider can be called.
     * That is far too slow to hold the caller's transaction open for. Sending it
     * here is also why this method used to differ from the push mirror, which has
     * always waited for the commit; SalonClosureService wraps itself in a
     * transaction and the message row would not exist yet for a worker that
     * picked the job up in between.
     *
     * The row is written now so the outbox has the audit trail even if the
     * dispatch throws, and the drain command picks up anything left behind.
     */
    private function mirrorToWhatsApp(Appointment $appointment, array $payload, string $event): void
    {
        try {
            $phone = $this->phoneFor($appointment);

            if (! $phone) {
                return;
            }

            $message = WhatsAppMessage::create([
                'user_id' => $appointment->customer_id,
                'to_phone' => $phone,
                'template' => $this->templateFor($event),
                'payload' => $payload,
                'related_appointment_id' => $appointment->id,
                'related_salon_id' => $appointment->salon_id,
                'status' => WhatsAppMessage::STATUS_QUEUED,
            ]);

            SendWhatsAppMessageJob::dispatch($message->id)->afterCommit();
        } catch (\Throwable $e) {
            Log::warning('Could not queue WhatsApp notification', [
                'appointment_id' => $appointment->id,
                'event' => $event,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * The provider's template name for an event.
     *
     * Read through one method so the event key — the thing this class and the
     * AISensy campaign config agree on — is translated to a template name in
     * exactly one place.
     */
    private function templateFor(string $event): string
    {
        $template = config("services.whatsapp.templates.{$event}");

        return is_string($template) && $template !== '' ? $template : $event;
    }

    /**
     * A money amount as it should appear inside a message.
     *
     * Same symbol and grouping the in-app notification uses, so a customer who
     * reads both is not left wondering whether they are two different amounts.
     */
    private function currency(float|int|string|null $amount): string
    {
        return config('app.currency_symbol', '₹')
            .number_format((float) $amount, 2);
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
