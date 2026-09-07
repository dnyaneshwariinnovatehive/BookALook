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
    | No provider is connected yet. The `log` driver records what would be sent
    | and leaves the row queued in whatsapp_messages; swap `driver` once a
    | WhatsApp Business account exists and bind the implementation in
    | AppServiceProvider.
    |
    */
    'whatsapp' => [
        'driver' => env('WHATSAPP_DRIVER', 'log'),
        'phone_number_id' => env('WHATSAPP_PHONE_NUMBER_ID'),
        'access_token' => env('WHATSAPP_ACCESS_TOKEN'),
        'default_country_code' => env('WHATSAPP_DEFAULT_COUNTRY_CODE', '91'),
        'templates' => [
            'salon_closure' => env('WHATSAPP_TEMPLATE_SALON_CLOSURE', 'salon_closure_reschedule'),
        ],
    ],

    'customer_app' => [
        // Used to build the free-reschedule link sent to customers.
        'deeplink_base' => env('CUSTOMER_APP_DEEPLINK_BASE', 'bookalook://customer'),
    ],

];
