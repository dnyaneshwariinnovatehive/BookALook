<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;

class CheckSubscriptions extends Command
{
    /**
     * The name and signature of the console command.
     *
     * @var string
     */
    protected $signature = 'app:check-subscriptions';

    /**
     * The console command description.
     *
     * @var string
     */
    protected $description = 'Check and expire subscriptions, and send expiry alerts';

    /**
     * Execute the console command.
     */
    public function handle()
    {
        $this->info('Starting subscription check...');
        $today = now()->format('Y-m-d');

        // 1. Expire past subscriptions
        $expiredCount = \App\Models\SalonSubscription::where('status', 'active')
            ->whereDate('end_date', '<', $today)
            ->update(['status' => 'expired']);
        
        $this->info("Expired {$expiredCount} subscriptions.");

        // 2. Alert for upcoming expiries
        $policy = \App\Models\PlatformPolicySetting::where('key', 'subscription_expiry_warning_days')->first();
        $warningDays = $policy ? (int) $policy->value : 3;
        
        $warningDate = now()->addDays($warningDays)->format('Y-m-d');

        $expiringSubscriptions = \App\Models\SalonSubscription::where('status', 'active')
            ->whereDate('end_date', '=', $warningDate)
            ->with('salon')
            ->get();

        foreach ($expiringSubscriptions as $sub) {
            // Check if salon has an assigned collaborator (from enquiries or a direct column)
            // The document says "Salons assigned to this Collaborator... Receives an alert"
            $collaboratorId = $sub->salon->admin_id; // For now, we alert the salon admin if we don't have a direct collaborator relationship
            
            // Generate Notification
            \App\Models\Notification::create([
                'user_id' => $collaboratorId,
                'title' => 'Subscription Expiring Soon',
                'message' => "The subscription for {$sub->salon->name} is expiring in {$warningDays} days.",
                'type' => 'alert',
                'is_read' => false
            ]);
            $this->info("Sent expiry alert to user {$collaboratorId} for salon {$sub->salon->name}.");
        }

        $this->info('Subscription check complete.');
    }
}
