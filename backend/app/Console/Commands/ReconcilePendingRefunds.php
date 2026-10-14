<?php

namespace App\Console\Commands;

use App\Services\BookingPaymentService;
use Illuminate\Console\Command;

/**
 * Sweeps through pending payment refunds that timed out or failed previously
 * and attempts durable reconciliation outside active user requests.
 */
class ReconcilePendingRefunds extends Command
{
    protected $signature = 'app:reconcile-pending-refunds';

    protected $aliases = ['bookalook:reconcile-refunds'];

    protected $description = 'Reconcile and retry pending payment refunds';

    public function handle(BookingPaymentService $payments): int
    {
        $recovered = $payments->reconcilePendingRefunds();

        $this->info($recovered === 0
            ? 'No pending refunds required reconciliation.'
            : "Successfully reconciled {$recovered} pending refund(s).");

        return self::SUCCESS;
    }
}
