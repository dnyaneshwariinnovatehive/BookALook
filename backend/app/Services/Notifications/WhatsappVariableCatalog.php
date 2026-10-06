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
                    'whatsapp_appointment_reminder',
                ],
            ],
            'salon_name' => [
                'key' => 'salon_name',
                'label' => 'Salon Name',
                'description' => 'The name of the business.',
                'example' => 'Glow Studio',
                'available_for' => [
                    'whatsapp_customer_birthday',
                    'whatsapp_25_day_reminder',
                    'whatsapp_appointment_reminder',
                ],
            ],
            'date_label' => [
                'key' => 'date_label',
                'label' => 'Date Label',
                'description' => 'A friendly date string for the appointment (e.g. Tomorrow at 10 AM).',
                'example' => 'Tomorrow at 10:00 AM',
                'available_for' => [
                    'whatsapp_appointment_reminder',
                ],
            ],
            'salon_address' => [
                'key' => 'salon_address',
                'label' => 'Salon Address',
                'description' => 'The full address of the salon.',
                'example' => '123 High Street',
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
