<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // 1. Rename existing new_booking_partner to new_booking_salon_admin
        DB::table('notification_templates')
            ->where('key', 'new_booking_partner')
            ->update([
                'key' => 'new_booking_salon_admin',
                'name' => 'New Booking (Salon Admin)'
            ]);

        // 2. Duplicate it into new_appointment_service_provider
        $adminTemplate = DB::table('notification_templates')->where('key', 'new_booking_salon_admin')->first();
        if ($adminTemplate) {
            DB::table('notification_templates')->insert([
                'id' => \Illuminate\Support\Str::uuid()->toString(),
                'key' => 'new_appointment_service_provider',
                'name' => 'New Appointment (Service Provider)',
                'type' => $adminTemplate->type,
                'category' => $adminTemplate->category,
                'audience' => 'service_provider',
                'default_title' => $adminTemplate->default_title,
                'default_message' => $adminTemplate->default_message,
                'default_push_title' => $adminTemplate->default_push_title,
                'default_push_message' => $adminTemplate->default_push_message,
                'action_config' => $adminTemplate->action_config,
                'schedule_config' => $adminTemplate->schedule_config,
                'channels' => $adminTemplate->channels,
                'available_variables' => $adminTemplate->available_variables,
                'is_enabled' => $adminTemplate->is_enabled,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        // 3. Update audiences for all templates
        $audienceMap = [
            'salon_closure_customer' => 'customer',
            'booking_created_customer' => 'customer',
            'booking_confirmed_customer' => 'customer',
            'booking_cancelled_customer' => 'customer',
            'booking_rescheduled_customer' => 'customer',
            'appointment_reminder_customer' => 'customer',
            'appointment_no_show_customer' => 'customer',
            'appointment_completed_customer' => 'customer',

            'provider_appointment_rescheduled_partner' => 'service_provider',
            'new_booking_salon_admin' => 'salon_admin',
            // new_appointment_service_provider is already set

            'assigned_salon_expiring_partner' => 'collaborator',
            'assigned_salon_expired_partner' => 'collaborator',
            'assigned_salon_renewed_partner' => 'collaborator',

            'subscription_expiring_partner' => 'salon_admin',
            'subscription_expired_partner' => 'salon_admin',
            'salon_reinstated_partner' => 'salon_admin',

            'complaint_warning_partner' => 'salon_admin',
            'complaint_suspension_partner' => 'salon_admin',

            'complaint_raised_superadmin' => 'superadmin',
        ];

        foreach ($audienceMap as $key => $audience) {
            DB::table('notification_templates')
                ->where('key', $key)
                ->update(['audience' => $audience]);
        }
    }

    public function down(): void
    {
        DB::table('notification_templates')->where('key', 'new_appointment_service_provider')->delete();
        DB::table('notification_templates')
            ->where('key', 'new_booking_salon_admin')
            ->update([
                'key' => 'new_booking_partner',
                'name' => 'New Booking'
            ]);
        
        // Revert all audiences
        DB::table('notification_templates')
            ->whereIn('audience', ['salon_admin', 'service_provider', 'collaborator'])
            ->update(['audience' => 'partner']);
    }
};
