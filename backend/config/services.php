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
    | `driver` picks who actually sends the message:
    |
    |   log         Writes each attempt to the log and contacts nobody, leaving
    |               the row `queued` so it can be inspected or drained later.
    |   meta_cloud  Meta's own Cloud API, addressed by template name.
    |   aisensy     AISensy, which sits in front of the same Meta API but
    |               addresses sends by *campaign* name instead.
    |
    | The marketing side needs two more values than the notification side did:
    | `verify_token`, which Meta echoes back when the webhook is subscribed, and
    | `app_secret`, which signs every incoming payload.
    |
    | The `templates` and `campaigns` blocks are keyed by event and are meant to be
    | read together. `templates` holds the Meta template name for an event;
    | `campaigns` holds the name of the live AISensy API campaign built on top of
    | that same template. A gateway joins them by event, so a send is described by
    | what happened rather than by a template string. `meta_cloud` ignores
    | `campaigns`; `aisensy` ignores nothing.
    |
    | An event with a template but no campaign is a configuration error and is
    | reported as a failed send rather than dropped — a message that silently
    | never arrives is the one failure nobody notices until a customer complains.
    |
    */
    'whatsapp' => [
        'driver' => env('WHATSAPP_DRIVER', 'log'),
        'phone_number_id' => env('WHATSAPP_PHONE_NUMBER_ID'),
        'access_token' => env('WHATSAPP_ACCESS_TOKEN'),
        'api_version' => env('WHATSAPP_API_VERSION', 'v21.0'),
        'verify_token' => env('WHATSAPP_VERIFY_TOKEN'),
        'app_secret' => env('WHATSAPP_APP_SECRET'),
        'default_country_code' => env('WHATSAPP_DEFAULT_COUNTRY_CODE', 91),

        // AISensy. The key is enough on its own; the endpoint and the source
        // label are overridable so a staging run can be told apart from live.
        'aisensy' => [
            'api_key' => env('WHATSAPP_AISENSY_API_KEY'),
            'base_url' => env('WHATSAPP_AISENSY_BASE_URL', 'https://backend.aisensy.com'),
            // AISensy segments contacts by this, so it should name this platform
            // and not the framework underneath it.
            'source' => env('WHATSAPP_AISENSY_SOURCE', 'bookalook'),
        ],

        'templates' => [
            'booking_confirmed' => env('WHATSAPP_TEMPLATE_BOOKING_CONFIRMED', 'bookalook_booking_confirmed'),
            'appointment_reminder' => env('WHATSAPP_TEMPLATE_APPOINTMENT_REMINDER', 'bookalook_appointment_reminder'),
            'appointment_cancelled' => env('WHATSAPP_TEMPLATE_APPOINTMENT_CANCELLED', 'bookalook_appointment_cancelled'),
            'salon_closure' => env('WHATSAPP_TEMPLATE_SALON_CLOSURE', 'salon_closure_reschedule'),
            'salon_deactivated' => env('WHATSAPP_TEMPLATE_SALON_DEACTIVATED', 'salon_deactivated_dues'),
        ],

        // AISensy API campaign names, one per event. Blank means "not configured",
        // and a send for a blank campaign is recorded as a failure naming the
        // variable to set rather than being attempted.
        'campaigns' => [
            'booking_confirmed' => env('WHATSAPP_CAMPAIGN_BOOKING_CONFIRMED', ''),
            'appointment_reminder' => env('WHATSAPP_CAMPAIGN_APPOINTMENT_REMINDER', 'BAL_apt_reminder'),
            'appointment_cancelled' => env('WHATSAPP_CAMPAIGN_APPOINTMENT_CANCELLED', ''),
            'salon_closure' => env('WHATSAPP_CAMPAIGN_SALON_CLOSURE', ''),
            'salon_deactivated' => env('WHATSAPP_CAMPAIGN_SALON_DEACTIVATED', ''),
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
