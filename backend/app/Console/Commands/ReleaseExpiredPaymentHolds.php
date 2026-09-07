<?php

namespace App\Console\Commands;

use App\Services\BookingPaymentService;
use Illuminate\Console\Command;

/**
 * Hand back the slots of checkouts nobody finished.
 *
 * Without this a customer who closes the app on the payment sheet keeps a chair
 * out of circulation forever.
 */
class ReleaseExpiredPaymentHolds extends Command
{
    protected $signature = 'app:release-payment-holds';

    protected $description = 'Release slots held by bookings whose payment window has expired';

    public function handle(BookingPaymentService $payments): int
    {
        $released = $payments->releaseExpiredHolds();

        $this->info($released === 0
            ? 'No expired payment holds.'
            : "Released {$released} expired payment hold(s).");

        return self::SUCCESS;
    }
}
