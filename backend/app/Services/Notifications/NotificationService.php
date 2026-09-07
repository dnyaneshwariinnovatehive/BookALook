<?php

namespace App\Services\Notifications;

use App\Models\Appointment;
use App\Models\Notification;
use App\Models\User;
use App\Models\WhatsAppMessage;
use Illuminate\Support\Facades\Log;

/**
 * One place to reach a customer.
 *
 * Every notification lands in the in-app inbox first — that is the channel we
 * actually control — and is then mirrored to WhatsApp on a best-effort basis.
 * A WhatsApp failure must never cost the customer their in-app notice, so the
 * mirror is wrapped and only logged.
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

        return Notification::create([
            'user_id' => $userId,
            'type' => $type,
            'title' => $title,
            'message' => $message,
            'data' => $data,
            'related_appointment_id' => $appointment?->id,
            'related_salon_id' => $appointment?->salon_id,
            'is_read' => false,
        ]);
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
