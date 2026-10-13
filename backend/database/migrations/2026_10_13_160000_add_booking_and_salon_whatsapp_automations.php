<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        $now = now();

        $automations = [
            [
                'key' => 'whatsapp_booking_confirmed',
                'name' => 'Booking Confirmed & Invoice',
                'description' => 'Send booking confirmation with invoice PDF attachment to customer when appointment is confirmed.',
                'audience' => 'Customer',
                'frequency_label' => 'On booking confirmation',
                'is_enabled' => false,
                'aisensy_campaign_name' => 'BAL_BOOKING_CONFIRMED',
                'lead_time_minutes' => null,
            ],
            [
                'key' => 'whatsapp_booking_reschedule',
                'name' => 'Booking Reschedule Required',
                'description' => 'Notify customer to reschedule for free when admin cancels or closes a salon day.',
                'audience' => 'Customer',
                'frequency_label' => 'On salon day closure',
                'is_enabled' => false,
                'aisensy_campaign_name' => 'bal_booking_reschedule',
                'lead_time_minutes' => null,
            ],
            [
                'key' => 'whatsapp_salon_deactivated',
                'name' => 'Salon Deactivation Statement',
                'description' => 'Send remaining accounts statement PDF to salon owner when salon is deactivated.',
                'audience' => 'Salon Owner',
                'frequency_label' => 'On salon deactivation',
                'is_enabled' => false,
                'aisensy_campaign_name' => 'BAL_salon_deactivated',
                'lead_time_minutes' => null,
            ],
        ];

        foreach ($automations as $automation) {
            $exists = DB::table('whatsapp_automations')->where('key', $automation['key'])->exists();
            if (!$exists) {
                DB::table('whatsapp_automations')->insert(array_merge($automation, [
                    'id' => (string) Str::uuid(),
                    'created_at' => $now,
                    'updated_at' => $now,
                ]));
            }
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        DB::table('whatsapp_automations')->whereIn('key', [
            'whatsapp_booking_confirmed',
            'whatsapp_booking_reschedule',
            'whatsapp_salon_deactivated',
        ])->delete();
    }
};
