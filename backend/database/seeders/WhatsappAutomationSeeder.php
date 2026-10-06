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
                'aisensy_campaign_name' => null,
                'lead_time_minutes' => null,
            ],
            [
                'key' => 'whatsapp_customer_birthday',
                'name' => 'Customer Birthday',
                'description' => 'Send birthday wishes automatically.',
                'audience' => 'Customer',
                'frequency_label' => 'Customer\'s birthday • Once per year',
                'is_enabled' => false,
                'aisensy_campaign_name' => null,
                'lead_time_minutes' => null,
            ],
            [
                'key' => 'whatsapp_25_day_reminder',
                'name' => '25-Day Reminder',
                'description' => 'Re-engage customers 25 days after a completed visit.',
                'audience' => 'Customer',
                'frequency_label' => '25 days after completed visit',
                'is_enabled' => false,
                'aisensy_campaign_name' => null,
                'lead_time_minutes' => null,
            ],
            [
                'key' => 'whatsapp_appointment_reminder',
                'name' => 'Appointment Reminder',
                'description' => 'Remind customers about their upcoming appointment.',
                'audience' => 'Customer',
                'frequency_label' => 'Before appointment',
                'is_enabled' => config('services.push.whatsapp_appointment_reminder_enabled', true),
                'aisensy_campaign_name' => config('services.whatsapp.campaigns.appointment_reminder'),
                'lead_time_minutes' => config('services.push.appointment_reminder_lead_hours', 2) * 60,
            ],
        ];

        foreach ($automations as $automation) {
            WhatsappAutomation::updateOrCreate(
                ['key' => $automation['key']],
                $automation
            );
        }
    }
}
