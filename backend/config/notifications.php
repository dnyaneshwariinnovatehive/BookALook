<?php

/*
 * How long in-app notifications are kept before the nightly prune deletes
 * them, for customers and partners alike. A read notification has done its
 * job and goes sooner; an unread one is given longer in case the person has
 * not opened the app. Their push delivery records go with them.
 */
return [
    'retention' => [
        'read_days' => (int) env('NOTIFICATION_RETENTION_READ_DAYS', 30),
        'unread_days' => (int) env('NOTIFICATION_RETENTION_UNREAD_DAYS', 90),
    ],
];
