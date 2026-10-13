<?php

namespace App\Services\Notifications;

class WhatsappVariableCatalog
{
    /**
     * Get all supported variables and their metadata.
     *
     * @return array
     */
    public static function all(): array
    {
        return [
            'customer_name' => [
                'key' => 'customer_name',
                'label' => 'Customer Name',
                'description' => 'The first name of the customer.',
                'example' => 'Rahul',
                'available_for' => [
                    'whatsapp_customer_birthday',
                    'whatsapp_25_day_reminder',
                    'whatsapp_booking_confirmed',
                ],
            ],
            'salon_name' => [
                'key' => 'salon_name',
                'label' => 'Salon Name',
                'description' => 'The name of the business.',
                'example' => 'Glow Studio',
                'available_for' => [
                    'whatsapp_appointment_reminder',
                    'whatsapp_booking_reschedule',
                ],
            ],
            'date_label' => [
                'key' => 'date_label',
                'label' => 'Appointment date & time',
                'description' => 'A friendly date string for the appointment.',
                'example' => 'October 12, 2026 at 4:30 PM',
                'available_for' => [
                    'whatsapp_booking_confirmed',
                    'whatsapp_booking_reschedule',
                    'whatsapp_appointment_reminder',
                ],
            ],
            'advance_amount' => [
                'key' => 'advance_amount',
                'label' => 'Advance Paid',
                'description' => 'The advance amount paid for booking.',
                'example' => '500',
                'available_for' => [
                    'whatsapp_booking_confirmed',
                ],
            ],
            'reschedule_reason' => [
                'key' => 'reschedule_reason',
                'label' => 'Closure / Reschedule Reason',
                'description' => 'The reason why the appointment cannot be completed.',
                'example' => 'The salon is closed for maintenance',
                'available_for' => [
                    'whatsapp_booking_reschedule',
                ],
            ],
            'reschedule_link' => [
                'key' => 'reschedule_link',
                'label' => 'Reschedule Link',
                'description' => 'The clickable link for the customer to reschedule for free.',
                'example' => 'https://bookalook.in/reschedule/sample-booking-link',
                'available_for' => [
                    'whatsapp_booking_reschedule',
                ],
            ],
            'salon_address' => [
                'key' => 'salon_address',
                'label' => 'Salon Address',
                'description' => 'The full address of the salon.',
                'example' => '123 MG Road, Pune',
                'available_for' => [
                    'whatsapp_appointment_reminder',
                ],
            ],
            'otp_code' => [
                'key' => 'otp_code',
                'label' => 'OTP Code',
                'description' => 'The 6-digit authentication code.',
                'example' => '123456',
                'available_for' => [
                    'whatsapp_otp',
                ],
            ],
        ];
    }

    /**
     * Get variables available for a specific automation key.
     *
     * @param string $automationKey
     * @return array
     */
    public static function forAutomation(string $automationKey): array
    {
        return array_values(array_filter(self::all(), function ($variable) use ($automationKey) {
            return in_array($automationKey, $variable['available_for']);
        }));
    }
}
