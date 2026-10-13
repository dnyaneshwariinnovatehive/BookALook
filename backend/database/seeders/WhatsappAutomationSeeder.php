<?php

namespace Database\Seeders;

use App\Models\WhatsappAutomation;
use Illuminate\Database\Seeder;

class WhatsappAutomationSeeder extends Seeder
{
    public function run(): void
    {
        $automations = [
            [
                'key' => 'whatsapp_otp',
                'name' => 'WhatsApp OTP',
                'description' => 'Send authentication OTP codes to users via WhatsApp.',
                'audience' => 'All Roles',
                'frequency_label' => 'On login/registration',
                'is_enabled' => false,
                'aisensy_campaign_name' => config('services.whatsapp.campaigns.otp', 'BAL_whatsapp_otp'),
                'lead_time_minutes' => null,
            ],
            [
                'key' => 'whatsapp_booking_confirmed',
                'name' => 'Booking Confirmed & Invoice',
                'description' => 'Send booking confirmation with invoice PDF attachment to customer when appointment is confirmed.',
                'audience' => 'Customer',
                'frequency_label' => 'On booking confirmation',
                'is_enabled' => false,
                'aisensy_campaign_name' => config('services.whatsapp.campaigns.booking_confirmed', 'BAL_BOOKING_CONFIRMED'),
                'lead_time_minutes' => null,
            ],
            [
                'key' => 'whatsapp_appointment_reminder',
                'name' => 'Appointment Reminder',
                'description' => 'Remind customers about their upcoming appointment.',
                'audience' => 'Customer',
                'frequency_label' => 'Before appointment',
                'is_enabled' => config('services.push.whatsapp_appointment_reminder_enabled', true),
                'aisensy_campaign_name' => config('services.whatsapp.campaigns.appointment_reminder', 'BAL_apt_reminder'),
                'lead_time_minutes' => config('services.push.appointment_reminder_lead_hours', 2) * 60,
            ],
            [
                'key' => 'whatsapp_booking_reschedule',
                'name' => 'Booking Reschedule Required',
                'description' => 'Notify customer to reschedule for free when admin cancels or closes a salon day.',
                'audience' => 'Customer',
                'frequency_label' => 'On salon day closure',
                'is_enabled' => false,
                'aisensy_campaign_name' => config('services.whatsapp.campaigns.booking_reschedule', 'bal_booking_reschedule'),
                'lead_time_minutes' => null,
            ],
            [
                'key' => 'whatsapp_customer_birthday',
                'name' => 'Customer Birthday',
                'description' => 'Send birthday wishes automatically.',
                'audience' => 'Customer',
                'frequency_label' => 'Customer\'s birthday • Once per year',
                'is_enabled' => false,
                'aisensy_campaign_name' => config('services.whatsapp.campaigns.customer_birthday', 'BAL_customer_birthday'),
                'lead_time_minutes' => null,
            ],
            [
                'key' => 'whatsapp_25_day_reminder',
                'name' => '25-Day Reminder',
                'description' => 'Re-engage customers 25 days after a completed visit.',
                'audience' => 'Customer',
                'frequency_label' => '25 days after completed visit',
                'is_enabled' => false,
                'aisensy_campaign_name' => config('services.whatsapp.campaigns.25_day_reminder', 'BAL_25_day_reminder'),
                'lead_time_minutes' => null,
            ],
            [
                'key' => 'whatsapp_salon_deactivated',
                'name' => 'Salon Deactivation Statement',
                'description' => 'Send remaining accounts statement PDF to salon owner when salon is deactivated.',
                'audience' => 'Salon Owner',
                'frequency_label' => 'On salon deactivation',
                'is_enabled' => false,
                'aisensy_campaign_name' => config('services.whatsapp.campaigns.salon_deactivated', 'BAL_salon_deactivated'),
                'lead_time_minutes' => null,
            ],
        ];

        foreach ($automations as $automation) {
            $existing = WhatsappAutomation::where('key', $automation['key'])->first();
            if ($existing) {
                $existing->update([
                    'name' => $automation['name'],
                    'description' => $automation['description'],
                    'audience' => $automation['audience'],
                    'frequency_label' => $automation['frequency_label'],
                    'aisensy_campaign_name' => $existing->aisensy_campaign_name ?: $automation['aisensy_campaign_name'],
                ]);
            } else {
                WhatsappAutomation::create($automation);
            }
        }
    }
}
