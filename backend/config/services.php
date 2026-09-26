<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'token' => env('POSTMARK_TOKEN'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'resend' => [
        'key' => env('RESEND_KEY'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | WhatsApp Business
    |--------------------------------------------------------------------------
    |
    | Set WHATSAPP_DRIVER=meta_cloud once a WhatsApp Business account exists and
    | the phone number id and access token below are filled in. Until then the
    | `log` driver records what would be sent and leaves the row queued in
    | whatsapp_messages, so campaigns can be built and tested end to end
    | without a provider — and nothing is ever mistaken for delivered.
    |
    | The marketing side needs two more values than the notification side did:
    | `verify_token`, which Meta echoes back when the webhook is subscribed, and
    | `app_secret`, which signs every incoming payload.
    |
    */
    'whatsapp' => [
        'driver' => env('WHATSAPP_DRIVER', 'log'),
        'phone_number_id' => env('WHATSAPP_PHONE_NUMBER_ID'),
        'access_token' => env('WHATSAPP_ACCESS_TOKEN'),
        'api_version' => env('WHATSAPP_API_VERSION', 'v21.0'),
        'verify_token' => env('WHATSAPP_VERIFY_TOKEN'),
        'app_secret' => env('WHATSAPP_APP_SECRET'),
        'default_country_code' => env('WHATSAPP_DEFAULT_COUNTRY_CODE', '91'),
        'templates' => [
            'salon_closure' => env('WHATSAPP_TEMPLATE_SALON_CLOSURE', 'salon_closure_reschedule'),
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Push Notifications
    |--------------------------------------------------------------------------
    |
    | PUSH_DRIVER is `log` in every environment for now. That driver writes each
    | attempted push to the log and contacts nobody, while still running the
    | whole pipeline — notification, queue, device lookup, delivery ledger — so
    | the backend can be built and tested ahead of the app.
    |
    | Set it to `fcm` once a Firebase project exists. Unlike the payment and
    | WhatsApp drivers, `fcm` does not fall back to the log driver when it is
    | unconfigured: it raises MissingFcmCredentials naming the variables that
    | are missing. Quietly degrading would report every delivery as `sent` and
    | make a broken server look like a working one.
    |
    | Credentials come from either an inline PEM (FCM_PRIVATE_KEY, whose newlines
    | arrive as literal \n and are normalised on read) or a service-account JSON
    | file that lives on the server and never in the repository
    | (FCM_CREDENTIALS_PATH — project id and client email are read from the same
    | file, so a server configures one path rather than four agreeing values).
    |
    | No credentials are committed, and the app must not need them: an
    | environment with none of them set keeps working on the log driver.
    |
    */
    'push' => [
        'driver' => env('PUSH_DRIVER', 'log'),
        'fcm' => [
            'project_id' => env('FCM_PROJECT_ID'),
            'client_email' => env('FCM_CLIENT_EMAIL'),
            // Either an inline PEM service-account key, or point at the file and
            // leave this empty. Never commit either one.
            'private_key' => env('FCM_PRIVATE_KEY'),
            'credentials_path' => env('FCM_CREDENTIALS_PATH'),
            // Must exist as a channel on the Android app or FCM drops the
            // notification instead of displaying it. The apps create it at
            // startup from the same id.
            'channel_id' => env('FCM_CHANNEL_ID', 'bookalook_notifications'),
        ],

        // How early, in hours, the scheduler tells a customer their appointment
        // is coming. 0 switches reminders off without touching the schedule.
        'appointment_reminder_lead_hours' => env('APPOINTMENT_REMINDER_LEAD_HOURS', 3),
    ],

    'customer_app' => [
        // Used to build the free-reschedule link sent to customers.
        'deeplink_base' => env('CUSTOMER_APP_DEEPLINK_BASE', 'bookalook://customer'),
    ],

    'razorpay' => [
        'driver' => env('PAYMENT_DRIVER', 'demo'), // fallback to demo if no keys
        'key_id' => env('RAZORPAY_KEY_ID'),
        'key_secret' => env('RAZORPAY_KEY_SECRET'),
        'demo_secret' => env('DEMO_PAYMENT_SECRET', 'test-secret'),
        'display_name' => env('PAYMENT_DISPLAY_NAME', 'BookALook'),
    ],

];
