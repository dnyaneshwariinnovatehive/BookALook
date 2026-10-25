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

// Reconcile and retry pending payment refunds that timed out or failed previously.
Schedule::command('app:reconcile-pending-refunds')->everyTenMinutes()->withoutOverlapping();

// Early each morning, before anyone opens the payouts screen. The command
// decides what is due: the weekly run every day, the monthly commission run
// only on the 1st. Nothing here moves money — it prepares the figures.
Schedule::command('app:generate-payouts')->dailyAt('04:00')->withoutOverlapping();

// Shortly after midnight, transition any untouched appointments from the previous
// day into a no-show state.
Schedule::command('app:mark-no-shows')->dailyAt('00:05')->withoutOverlapping();

// Appointment reminders. Every fifteen minutes, not once an hour: the command
// recomputes its own window from the data on each pass, so it does not care
// when it runs, and running it often is what makes a missed tick cost nothing.
// It is idempotent through a dedupe key, so running it twice costs nothing
// either. withoutOverlapping because two passes at once would be two schedulers
// racing over the same window.
Schedule::command('app:send-appointment-reminders')->everyFifteenMinutes()->withoutOverlapping();

// The WhatsApp outbox safety net. Messages are dispatched as jobs the moment they
// are written, so in normal operation this finds nothing — it exists for the ones
// that were written while no provider was configured, or while the queue was down.
// The five-minute age floor is what lets it run every minute without racing a busy
// worker, and the command claims each row before dispatching so the two cannot both
// decide to send the same message.
Schedule::command('app:drain-whatsapp-outbox')->everyMinute()->withoutOverlapping();

// Sends the 25-day reminders and birthday messages. Whether each runs is
// decided only by its switch in SuperAdmin's WhatsApp automations; salons have no say.
Schedule::command('app:send-automated-messages')->dailyAt('09:00')->withoutOverlapping();

// Old in-app notifications, customers' and partners' alike, so the table does
// not grow forever: read ones after 30 days, any after 90 (both set in
// config/notifications.php). Their push delivery rows cascade with them.
// Overnight, when nobody is reading their inbox.
Schedule::command('model:prune', ['--model' => [\App\Models\Notification::class]])
    ->dailyAt('03:30')
    ->withoutOverlapping();
