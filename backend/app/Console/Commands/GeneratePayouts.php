<?php

namespace App\Console\Commands;

use App\Services\PayoutService;
use App\Support\PayoutCycle;
use Carbon\Carbon;
use Illuminate\Console\Command;

/**
 * Builds the payout runs that have just closed.
 *
 * Sits on a daily schedule and works out for itself what is due:
 *
 *  - The weekly run, for salons on a Subscription Plan, is rebuilt every day.
 *    Rebuilding a pending cycle is safe and picks up late completions; a
 *    distributed one is frozen and left alone.
 *  - The monthly run, for salons on the Commission Model, only fires on the
 *    1st, which is when a month is settled.
 *
 * Nothing here moves money. It only prepares the figures for SuperAdmin to
 * approve and distribute.
 */
class GeneratePayouts extends Command
{
    protected $signature = 'app:generate-payouts
        {--force-monthly : Build the monthly commission run even when today is not the 1st}
        {--date= : Treat this date as today, for backfilling a missed run}';

    protected $description = 'Calculate the weekly and monthly salon payout cycles that have closed';

    public function handle(PayoutService $payouts): int
    {
        $on = $this->option('date') ? Carbon::parse($this->option('date')) : Carbon::today();

        $result = $payouts->generateDue($on, force: (bool) $this->option('force-monthly'));

        $this->components->twoColumnDetail(
            'weekly · subscription plans',
            sprintf('%d payout(s) for %s', $result['weekly']['payouts'], $result['weekly']['start'])
        );

        if ($result['monthly']) {
            $this->components->twoColumnDetail(
                'monthly · commission model',
                sprintf('%d payout(s) for %s', $result['monthly']['payouts'], $result['monthly']['start'])
            );
        } else {
            $this->components->twoColumnDetail(
                'monthly · commission model',
                'not due — settles on the 1st'
            );
        }

        return self::SUCCESS;
    }
}
