<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

use Illuminate\Support\Facades\Schedule;

// Hourly: lapsed plans are expired on every pass so nothing is a day stale,
// while the renewal reminders only fire at the configured hour.
Schedule::command('app:check-subscriptions')->hourly();

// A held slot is unsellable, so lapsed holds are swept often — the customer on
// the payment sheet has ten minutes, the next customer should not wait longer.
Schedule::command('app:release-payment-holds')->everyMinute()->withoutOverlapping();

// Early each morning, before anyone opens the payouts screen. The command
// decides what is due: the weekly run every day, the monthly commission run
// only on the 1st. Nothing here moves money — it prepares the figures.
Schedule::command('app:generate-payouts')->dailyAt('04:00')->withoutOverlapping();
