<?php

namespace Database\Seeders;

use App\Models\NotificationTemplate;
use App\Support\Notifications\NotificationType;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

class NotificationTemplateSeeder extends Seeder
{
    /**
     * Run the database seeds.
     */
    public function run(): void
    {
        $templates = [
            // Customer Events
            [
                'key' => 'salon_closure_customer',
                'type' => NotificationType::SALON_CLOSURE,
                'audience' => 'customer',
                'default_title' => 'Your appointment needs a new time',
                'default_message' => '{{salon_name}} is closed on {{date_label}}{{reason}}. Your booking has been released and you can pick a new slot free of charge — the amount you already paid carries over.',
                'available_variables' => ['salon_name', 'date_label', 'reason'],
                'channels' => ['in_app', 'push', 'whatsapp'],
            ],
            [
                'key' => 'booking_created_customer',
                'type' => NotificationType::BOOKING_CREATED,
                'audience' => 'customer',
                'default_title' => 'Booking created — complete the payment',
                'default_message' => 'Your booking at {{salon_name}} is held. Pay {{advance_due}} to confirm it.',
                'available_variables' => ['salon_name', 'advance_due'],
                'channels' => ['in_app', 'push'],
            ],
            [
                'key' => 'booking_confirmed_customer',
                'type' => NotificationType::BOOKING_CONFIRMED,
                'audience' => 'customer',
                'default_title' => 'Booking confirmed',
                'default_message' => 'Your booking at {{salon_name}} on {{date_label}} is confirmed.',
                'available_variables' => ['salon_name', 'date_label', 'advance_amount'],
                'channels' => ['in_app', 'push', 'whatsapp'],
            ],
            [
                'key' => 'booking_cancelled_customer',
                'type' => NotificationType::BOOKING_CANCELLED,
                'audience' => 'customer',
                'default_title' => 'Booking cancelled',
                'default_message' => 'Your booking at {{salon_name}} on {{date_label}} has been cancelled.',
                'available_variables' => ['salon_name', 'date_label', 'reason'],
                'channels' => ['in_app', 'push', 'whatsapp'],
            ],
            [
                'key' => 'booking_rescheduled_customer',
                'type' => NotificationType::BOOKING_RESCHEDULED,
                'audience' => 'customer',
                'default_title' => 'Booking rescheduled',
                'default_message' => 'Your booking at {{salon_name}} has moved to {{date_label}}.',
                'available_variables' => ['salon_name', 'date_label'],
                'channels' => ['in_app', 'push'],
            ],
            [
                'key' => 'appointment_reminder_customer',
                'type' => NotificationType::APPOINTMENT_REMINDER,
                'audience' => 'customer',
                'default_title' => 'Reminder: your appointment is coming up',
                'default_message' => 'You are booked at {{salon_name}} on {{date_label}}.',
                'available_variables' => ['salon_name', 'date_label', 'salon_address'],
                'channels' => ['in_app', 'push', 'whatsapp'],
            ],
            [
                'key' => 'appointment_no_show_customer',
                'type' => NotificationType::APPOINTMENT_NO_SHOW,
                'audience' => 'customer',
                'default_title' => 'Your appointment was missed',
                'default_message' => 'The booking at {{salon_name}} was marked as missed because nobody checked in.',
                'available_variables' => ['salon_name'],
                'channels' => ['in_app', 'push'],
            ],
            [
                'key' => 'appointment_completed_customer',
                'type' => NotificationType::APPOINTMENT_COMPLETED,
                'audience' => 'customer',
                'default_title' => 'How was your visit?',
                'default_message' => 'Your appointment at {{salon_name}} is complete. Rate your experience.',
                'available_variables' => ['salon_name'],
                'channels' => ['in_app', 'push'],
            ],

            // Partner Events
            [
                'key' => 'provider_appointment_rescheduled_partner',
                'type' => NotificationType::PROVIDER_APPOINTMENT_RESCHEDULED,
                'audience' => 'partner',
                'default_title' => 'Appointment Rescheduled',
                'default_message' => 'Your appointment with {{customer_name}} on {{date_label}} has been rescheduled by the customer.',
                'available_variables' => ['customer_name', 'date_label'],
                'channels' => ['in_app', 'push'],
            ],
            [
                'key' => 'new_booking_partner',
                'type' => NotificationType::NEW_BOOKING,
                'audience' => 'partner',
                'default_title' => 'New booking',
                'default_message' => '{{customer_name}} booked {{date_label}} at {{salon_name}}.',
                'available_variables' => ['customer_name', 'date_label', 'salon_name'],
                'channels' => ['in_app', 'push'],
            ],
            [
                'key' => 'assigned_salon_expiring_partner',
                'type' => NotificationType::ASSIGNED_SALON_EXPIRING,
                'audience' => 'partner',
                'default_title' => '{{salon_name}}\'s plan ends {{when}}',
                'default_message' => 'A salon you onboarded is about to stop taking bookings. Give {{owner_name}} a call before it goes offline.',
                'available_variables' => ['salon_name', 'when', 'owner_name'],
                'channels' => ['in_app', 'push'],
            ],
            [
                'key' => 'assigned_salon_expired_partner',
                'type' => NotificationType::ASSIGNED_SALON_EXPIRING, // reused type from before
                'audience' => 'partner',
                'default_title' => '{{salon_name}}\'s plan has expired',
                'default_message' => '{{salon_name}} is no longer taking bookings. Call {{owner_name}} to get it back online.',
                'available_variables' => ['salon_name', 'owner_name'],
                'channels' => ['in_app', 'push'],
            ],
            [
                'key' => 'assigned_salon_renewed_partner',
                'type' => NotificationType::ASSIGNED_SALON_RENEWED,
                'audience' => 'partner',
                'default_title' => '{{salon_name}} is renewed',
                'default_message' => '{{owner_name}} renewed {{plan_name}}. {{live_until_msg}}',
                'available_variables' => ['salon_name', 'owner_name', 'plan_name', 'live_until_msg'],
                'channels' => ['in_app', 'push'],
            ],
            // Owner / Admin notifications
            [
                'key' => 'subscription_expiring_partner',
                'type' => 'subscription_expiring',
                'audience' => 'partner',
                'default_title' => 'Your plan ends in {{days_left}} day{{s}}',
                'default_message' => '{{salon_name}} stops taking online bookings when the plan ends. Renew now to stay listed.',
                'available_variables' => ['days_left', 's', 'salon_name'],
                'channels' => ['in_app', 'push'],
            ],
            [
                'key' => 'subscription_expired_partner',
                'type' => 'subscription_expired',
                'audience' => 'partner',
                'default_title' => 'Your salon is offline',
                'default_message' => '{{salon_name}} has been hidden from customers for {{days_down}}. Your staff cannot use the app either. Renew to go back online.',
                'available_variables' => ['days_down', 'salon_name'],
                'channels' => ['in_app', 'push'],
            ],
            [
                'key' => 'salon_reinstated_partner',
                'type' => 'salon_reinstated',
                'audience' => 'partner',
                'default_title' => 'Your salon is back online',
                'default_message' => '{{salon_name}} is live again and can take bookings.',
                'available_variables' => ['salon_name'],
                'channels' => ['in_app', 'push'],
            ],
            [
                'key' => 'complaint_warning_partner',
                'type' => 'complaint_warning',
                'audience' => 'partner',
                'default_title' => 'A warning from BookALook',
                'default_message' => '{{admin_message}}',
                'available_variables' => ['salon_name', 'admin_message'],
                'channels' => ['in_app', 'push'],
            ],
            [
                'key' => 'complaint_suspension_partner',
                'type' => 'salon_suspended',
                'audience' => 'partner',
                'default_title' => 'Your salon has been suspended',
                'default_message' => '{{admin_message}}',
                'available_variables' => ['salon_name', 'admin_message'],
                'channels' => ['in_app', 'push'],
            ],
            // SuperAdmin
            [
                'key' => 'complaint_raised_superadmin',
                'type' => 'complaint_raised',
                'audience' => 'superadmin',
                'default_title' => 'Complaint about {{salon_name}}',
                'default_message' => '{{complaint_subject}}',
                'available_variables' => ['salon_name', 'complaint_subject'],
                'channels' => ['in_app'],
            ],
        ];

        foreach ($templates as $template) {
            NotificationTemplate::firstOrCreate(
                ['key' => $template['key']],
                $template
            );
        }
    }
}
