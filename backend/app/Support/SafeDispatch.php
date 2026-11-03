<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Queue a job for work whose record is already in PostgreSQL (an outbox row).
 *
 * The queue is only the transport. If it cannot take the job — Redis down,
 * a timeout — the business operation that created the row has already
 * committed and must not be reported as failed. The failure is logged
 * ("queue.dispatch_failed") and the row stays where the recovery sweep
 * (app:recover-queued-work, every minute) finds it and queues it again.
 *
 * The push happens after the surrounding transaction commits, so a worker can
 * never pick up a job for a row that is not visible yet, and a rolled-back
 * transaction queues nothing.
 *
 * Only use this where such a recovery path exists for the job.
 */
final class SafeDispatch
{
    /** @param array<string, mixed> $context what to log if it fails (ids only, never contents) */
    public static function afterCommit(object $job, array $context = []): void
    {
        DB::afterCommit(static function () use ($job, $context) {
            try {
                dispatch($job);
            } catch (Throwable $e) {
                Log::error('queue.dispatch_failed', $context + [
                    'job' => $job::class,
                    'error' => $e->getMessage(),
                    'recovery' => 'app:recover-queued-work will queue it again',
                ]);
            }
        });
    }
}
