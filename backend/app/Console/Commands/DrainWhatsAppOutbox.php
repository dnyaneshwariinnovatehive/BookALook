<?php

namespace App\Console\Commands;

use App\Jobs\SendWhatsAppMessageJob;
use App\Models\WhatsAppMessage;
use App\Services\Notifications\LogWhatsAppGateway;
use App\Services\Notifications\WhatsAppGateway;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Picks up WhatsApp messages that were written to the outbox but never handed to
 * a provider.
 *
 * The normal path is that every message is dispatched as a job the moment it is
 * written, and this command exists for the cases that path cannot cover:
 *
 *   - The driver was `log` when the message was written, so it was left `queued`
 *     deliberately. Switching to a real provider should not strand that backlog.
 *   - The queue was down, or the worker was not running, when the job was pushed.
 *   - A dispatch threw, which the callers log and swallow rather than letting a
 *     booking fail.
 *
 * All three produce the same visible symptom — a message that will never be sent
 * and no error anywhere, because the row sits at `queued` looking exactly like a
 * message that is merely waiting its turn. Recomputed from the data on every pass
 * and idempotent, so a missed tick costs one delayed message and a repeated tick
 * costs nothing.
 *
 * Two conditions keep it from becoming the thing it exists to prevent.
 *
 * It does not run at all while the driver cannot send. `LogWhatsAppGateway` leaves
 * rows `queued` on purpose, so a pass over the backlog while it is the driver in
 * use would redispatch every message once a minute, each pass ending with the row
 * still `queued`. The backlog would be indistinguishable from a failing queue, and
 * the log would fill with lines that say nothing happened.
 *
 * And it only claims rows that no provider has ever tried — `attempts = 0`. A row
 * that a provider has already been handed is either on its way out or has been
 * lost in a way this command cannot see, and sending it a second time would put
 * two identical messages in the customer's chat. Untouched rows are also the ones
 * this command is for: they are stranded precisely because nothing tried them.
 */
class DrainWhatsAppOutbox extends Command
{
    protected $signature = 'app:drain-whatsapp-outbox
                            {--limit=200 : Maximum messages to dispatch per pass}
                            {--older-than=5 : Only claim messages queued at least this many minutes ago}
                            {--dry-run : List what would be dispatched without sending anything}';

    protected $description = 'Dispatches queued WhatsApp messages that never reached a provider';

    public function handle(WhatsAppGateway $gateway): int
    {
        // Checked before the dry run too, so `--dry-run` answers the question the
        // operator is actually asking — "would this send anything?" — rather than
        // reporting a backlog that provably cannot move.
        if ($gateway instanceof LogWhatsAppGateway) {
            $this->info('WhatsApp is on the log driver, so there is nothing this pass could send.');

            return self::SUCCESS;
        }

        $limit = min(1000, max(1, (int) $this->option('limit')));
        $olderThan = max(0, (int) $this->option('older-than'));

        if ($this->option('dry-run')) {
            return $this->report($this->stranded($limit, $olderThan)->count(), true);
        }

        return $this->report($this->claim($limit, $olderThan), false);
    }

    /**
     * Messages old enough to be considered stranded, oldest first.
     *
     * The age floor is what makes this safe to run every minute. Without it the
     * pass would race the queue worker: a message dispatched a second ago is
     * still `queued` until its job runs, and two workers claiming it means the
     * customer gets it twice.
     *
     * @return \Illuminate\Support\Collection<int, WhatsAppMessage>
     */
    private function stranded(int $limit, int $olderThanMinutes)
    {
        return WhatsAppMessage::query()
            ->where('status', WhatsAppMessage::STATUS_QUEUED)
            ->where('attempts', 0)
            ->when($olderThanMinutes > 0, fn ($q) => $q->where(
                'created_at',
                '<=',
                now()->subMinutes($olderThanMinutes)
            ))
            ->oldest('created_at')
            ->limit($limit)
            ->get();
    }

    /**
     * Dispatch stranded messages, re-checking each row immediately before it goes.
     *
     * One transaction per row rather than one for the batch, so work on a message
     * is released the moment it is dispatched instead of being held across every
     * other message in the backlog.
     *
     * The transaction here is not a claim. It narrows the window between reading a
     * row and dispatching it, and stops two passes running concurrently from
     * dispatching the same one; it cannot stop the next pass from dispatching a row
     * this pass just dispatched, because the row is unchanged and still `queued`
     * when the lock is dropped. That is left to `attempts` and the age floor — a
     * message that has been handed out has its attempts counted by the gateway, so
     * it stops matching a query this command runs.
     *
     * @return int Number dispatched.
     */
    private function claim(int $limit, int $olderThanMinutes): int
    {
        $dispatched = 0;

        foreach ($this->stranded($limit, $olderThanMinutes) as $candidate) {
            $claimed = DB::transaction(function () use ($candidate) {
                $row = WhatsAppMessage::query()
                    ->whereKey($candidate->id)
                    ->where('status', WhatsAppMessage::STATUS_QUEUED)
                    ->where('attempts', 0)
                    ->lockForUpdate()
                    ->first();

                // Already sent, already failed, or taken since the listing. Not
                // this pass's to send.
                if (! $row) {
                    return false;
                }

                SendWhatsAppMessageJob::dispatch($row->id);

                return true;
            });

            if ($claimed) {
                $dispatched++;
            }
        }

        return $dispatched;
    }

    private function report(int $count, bool $dryRun): int
    {
        if ($count === 0) {
            $this->info('No queued WhatsApp messages are waiting to be dispatched.');

            return self::SUCCESS;
        }

        $this->info(sprintf(
            '%s %d queued WhatsApp message(s).%s',
            $dryRun ? 'Would dispatch' : 'Dispatched',
            $count,
            $dryRun ? ' (dry run, nothing was sent)' : ''
        ));

        return self::SUCCESS;
    }
}