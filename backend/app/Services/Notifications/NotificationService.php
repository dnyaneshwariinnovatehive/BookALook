<?php

namespace App\Services\Notifications;

use App\Jobs\SendPushNotificationJob;
use App\Models\Appointment;
use App\Models\Notification;
use App\Models\User;
use App\Models\WhatsAppMessage;
use Illuminate\Support\Facades\Log;

/**
 * One place to reach a customer.
 *
 * Every notification lands in the in-app inbox first — that is the channel we
 * actually control — and is then mirrored to WhatsApp on a best-effort basis,
 * with a push queued for the customer's registered phones. A failure on either
 * mirror must never cost the customer their in-app notice, so both are wrapped
 * and only logged.
 *
 * Push is queued rather than sent inline because the caller is usually inside
 * a database transaction, and a device lookup plus a provider call in the
 * middle of one would hold a booking open for a network round trip.
 */
class NotificationService
{
    public const TYPE_SALON_CLOSED = 'salon_closure';

    public function __construct(private WhatsAppGateway $whatsapp)
    {
    }

    /**
     * Tell a customer their booking lost its day and they can move it for free.
     */
    public function appointmentNeedsReschedule(
        Appointment $appointment,
        string $salonName,
        string $dateLabel,
        ?string $reason
    ): Notification {
        $because = $reason ? " ({$reason})" : '';

        $notification = $this->record(
            userId: $appointment->customer_id,
            type: self::TYPE_SALON_CLOSED,
            title: 'Your appointment needs a new time',
            message: "{$salonName} is closed on {$dateLabel}{$because}. "
                . 'Your booking has been released and you can pick a new slot free of charge — '
                . 'the amount you already paid carries over.',
            appointment: $appointment,
            data: [
                'action' => 'reschedule_appointment',
                'appointment_id' => $appointment->id,
                'free_reschedule' => true,
                'deeplink' => $this->rescheduleDeeplink($appointment->id),
            ]
        );

        if ($notification) {
            $this->mirrorToWhatsApp($appointment, [
                'salon_name' => $salonName,
                'appointment_date' => $dateLabel,
                'reason' => $reason,
                'reschedule_link' => $this->rescheduleDeeplink($appointment->id),
            ]);
        }

        return $notification ?? new Notification();
    }

    /**
     * Alert a service provider that a customer rescheduled their appointment,
     * freeing up this slot.
     */
    public function providerAppointmentRescheduled(Appointment $appointment): Notification
    {
        $provider = $appointment->appointedProvider;
        if (! $provider || ! $provider->user_id) {
            return new Notification();
        }

        $customerName = $appointment->customer ? $appointment->customer->name : $appointment->walk_in_customer_name;
        $dateLabel = \Carbon\Carbon::parse($appointment->appointment_date)->format('M d, Y') . ' at ' . \Carbon\Carbon::parse($appointment->start_time)->format('h:i A');

        return $this->record(
            userId: $provider->user_id,
            type: 'general', // Using 'general' as a fallback, or could use 'cancellation'
            title: 'Appointment Rescheduled',
            message: "Your appointment with {$customerName} on {$dateLabel} has been rescheduled by the customer.",
            appointment: $appointment,
            data: [
                'action' => 'appointment_rescheduled',
                'appointment_id' => $appointment->id,
            ]
        ) ?? new Notification();
    }

    /**
     * Write an in-app notification. Walk-in bookings have no customer account,
     * so there is nobody to notify — those are the salon's phone call to make.
     */
    private function record(
        ?string $userId,
        string $type,
        string $title,
        string $message,
        ?Appointment $appointment = null,
        array $data = []
    ): ?Notification {
        if (! $userId) {
            return null;
        }

        $notification = Notification::create([
            'user_id' => $userId,
            'type' => $type,
            'title' => $title,
            'message' => $message,
            'data' => $data,
            'related_appointment_id' => $appointment?->id,
            'related_salon_id' => $appointment?->salon_id,
            'is_read' => false,
        ]);

        // Queued from here, rather than from each caller, so a new notification
        // cannot be added without also being pushed.
        $this->mirrorToPush($notification);

        return $notification;
    }

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
        $base = rtrim((string) config('services.customer_app.deeplink_base'), '/');

        return "{$base}/appointments/{$appointmentId}/reschedule";
    }
}
