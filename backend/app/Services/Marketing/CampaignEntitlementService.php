<?php

namespace App\Services\Marketing;

use App\Models\Campaign;
use App\Models\CampaignTemplate;
use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPlan;
use App\Models\WhatsAppMessage;
use Illuminate\Support\Carbon;

/**
 * What a salon's plan actually entitles it to, enforced server-side.
 *
 * Two allowances run at once and either can bind: campaigns per cycle and
 * messages per cycle. Which one is doing the work is a commercial decision, not
 * a structural one, so a limit of zero means "this allowance is not in use" and
 * a plan can be capped by either, both, or neither without a code change.
 *
 * The cycle is the subscription's own billing period, not the calendar month.
 * A salon that renews on the 20th gets its allowance back on the 20th, and a
 * campaign records the period it was charged to at send time — deriving it
 * afterwards would move older campaigns between cycles as the salon renews.
 */
class CampaignEntitlementService
{
    public function __construct(private MarketingSettings $settings)
    {
    }

    /**
     * Everything the partner app needs to draw the quota meter and decide what
     * to grey out.
     *
     * @return array<string, mixed>
     */
    public function summaryFor(Salon $salon): array
    {
        $subscription = $this->activeSubscription($salon);
        $plan = $subscription?->plan;

        if (! $plan) {
            return [
                'has_plan' => false,
                'can_send' => false,
                'reason' => 'This salon has no active subscription, so marketing is switched off.',
                'features' => $this->featuresFor(null),
            ];
        }

        [$cycleStart, $cycleEnd] = $this->cycleFor($subscription);

        $campaignsUsed = $this->campaignsUsed($salon, $cycleStart, $cycleEnd);
        $messagesUsed = $this->messagesUsed($salon, $cycleStart, $cycleEnd);

        $campaignLimit = (int) $plan->whatsapp_campaign_limit;
        $messageLimit = (int) $plan->whatsapp_message_limit;

        return [
            'has_plan' => true,
            'plan_name' => $plan->name,
            'cycle_start' => $cycleStart->toDateString(),
            'cycle_end' => $cycleEnd->toDateString(),
            'days_left_in_cycle' => max(0, now()->startOfDay()->diffInDays($cycleEnd, false)),

            'campaigns' => [
                'limit' => $campaignLimit,
                'used' => $campaignsUsed,
                // Null rather than a big number: "unlimited" is a different
                // thing from "lots left" and the UI should say so.
                'remaining' => $campaignLimit > 0 ? max(0, $campaignLimit - $campaignsUsed) : null,
                'unlimited' => $campaignLimit === 0,
            ],
            'messages' => [
                'limit' => $messageLimit,
                'used' => $messagesUsed,
                'remaining' => $messageLimit > 0 ? max(0, $messageLimit - $messagesUsed) : null,
                'unlimited' => $messageLimit === 0,
            ],

            'daily_cap' => $this->settings->dailyCap(),
            'sent_today' => $this->messagesSentToday($salon),
            'quiet_hours' => [
                'start' => $this->settings->quietHoursStart(),
                'end' => $this->settings->quietHoursEnd(),
                'active_now' => $this->settings->isQuietHour(),
            ],

            'can_send' => $this->campaignsRemaining($salon) !== 0,
            'features' => $this->featuresFor($plan),
        ];
    }

    /**
     * Which audience segments and templates this plan may use.
     *
     * The spec puts segmentation, service-based and high-value targeting behind
     * Growth; everything else is available to anyone who is paying.
     *
     * @return array<string, bool|string>
     */
    public function featuresFor(?SubscriptionPlan $plan): array
    {
        return [
            'segmentation' => (bool) ($plan->has_customer_segmentation ?? false),
            'service_targeting' => (bool) ($plan->has_service_based_targeting ?? false),
            'high_value_targeting' => (bool) ($plan->has_high_value_targeting ?? false),
            'advanced_insights' => (bool) ($plan->has_advanced_insights ?? false),
            'upsell' => $plan->has_upsell_recommendations ?? 'none',
            'cross_sell' => $plan->has_cross_sell_recommendations ?? 'none',
            'priority_visibility' => (bool) ($plan->has_priority_visibility ?? false),
        ];
    }

    /**
     * May this salon start this campaign right now?
     *
     * Returns null when it may, and a reason when it may not. Callers turn the
     * reason straight into the upgrade prompt the spec asks for.
     */
    public function refusalFor(Salon $salon, CampaignTemplate $template, int $recipientCount): ?array
    {
        $subscription = $this->activeSubscription($salon);
        $plan = $subscription?->plan;

        if (! $plan) {
            return $this->refusal('no_subscription', 'Marketing needs an active subscription.');
        }

        if ($template->requiresGrowth() && ! $plan->has_customer_segmentation) {
            return $this->refusal(
                'upgrade_required',
                "\"{$template->name}\" is part of the Growth plan.",
                upgrade: true
            );
        }

        $remaining = $this->campaignsRemaining($salon);

        if ($remaining !== null && $remaining <= 0) {
            [, $cycleEnd] = $this->cycleFor($subscription);

            $limit = (int) $plan->whatsapp_campaign_limit;

            return $this->refusal(
                'campaign_limit_reached',
                sprintf(
                    'This plan allows %d campaign%s per billing cycle, and %s been used. The allowance resets on %s.',
                    $limit,
                    $limit === 1 ? '' : 's',
                    $limit === 1 ? 'it has' : 'all of them have',
                    $cycleEnd->format('j M')
                ),
                upgrade: true
            );
        }

        $messagesLeft = $this->messagesRemaining($salon);

        // Not a refusal. A campaign that reaches most of its audience is worth
        // more to the salon than one the platform declined to send at all, so
        // the overflow is skipped per recipient and reported.
        if ($messagesLeft !== null && $recipientCount > $messagesLeft && $messagesLeft <= 0) {
            [, $cycleEnd] = $this->cycleFor($subscription);

            return $this->refusal(
                'message_limit_reached',
                sprintf(
                    'This plan\'s %d messages for the cycle have all been used. The allowance resets on %s.',
                    (int) $plan->whatsapp_message_limit,
                    $cycleEnd->format('j M')
                ),
                upgrade: true
            );
        }

        return null;
    }

    /** How many more messages may go out this cycle; null when uncapped. */
    public function messagesRemaining(Salon $salon): ?int
    {
        $subscription = $this->activeSubscription($salon);
        $limit = (int) ($subscription?->plan?->whatsapp_message_limit ?? 0);

        if (! $subscription || $limit === 0) {
            return null;
        }

        [$start, $end] = $this->cycleFor($subscription);

        return max(0, $limit - $this->messagesUsed($salon, $start, $end));
    }

    public function campaignsRemaining(Salon $salon): ?int
    {
        $subscription = $this->activeSubscription($salon);

        if (! $subscription) {
            return 0;
        }

        $limit = (int) ($subscription->plan?->whatsapp_campaign_limit ?? 0);

        if ($limit === 0) {
            return null;
        }

        [$start, $end] = $this->cycleFor($subscription);

        return max(0, $limit - $this->campaignsUsed($salon, $start, $end));
    }

    /** What is left of today's cap; null when uncapped. */
    public function dailyRemaining(Salon $salon): ?int
    {
        $cap = $this->settings->dailyCap();

        return $cap === 0 ? null : max(0, $cap - $this->messagesSentToday($salon));
    }

    /**
     * The billing period a campaign sent now belongs to.
     *
     * @return array{0: Carbon, 1: Carbon}
     */
    public function cycleFor(SalonSubscription $subscription): array
    {
        return [
            Carbon::parse($subscription->start_date)->startOfDay(),
            Carbon::parse($subscription->end_date)->endOfDay(),
        ];
    }

    public function activeSubscription(Salon $salon): ?SalonSubscription
    {
        return SalonSubscription::with('plan')
            ->where('salon_id', $salon->id)
            ->where('status', 'active')
            ->whereDate('end_date', '>=', now()->toDateString())
            ->orderByDesc('end_date')
            ->first();
    }

    private function campaignsUsed(Salon $salon, Carbon $start, Carbon $end): int
    {
        return Campaign::where('salon_id', $salon->id)
            ->counted()
            ->whereDate('created_at', '>=', $start->toDateString())
            ->whereDate('created_at', '<=', $end->toDateString())
            ->count();
    }

    private function messagesUsed(Salon $salon, Carbon $start, Carbon $end): int
    {
        return WhatsAppMessage::where('related_salon_id', $salon->id)
            ->marketing()
            ->billable()
            ->whereBetween('created_at', [$start, $end])
            ->count();
    }

    private function messagesSentToday(Salon $salon): int
    {
        return WhatsAppMessage::where('related_salon_id', $salon->id)
            ->marketing()
            ->billable()
            ->whereDate('created_at', now()->toDateString())
            ->count();
    }

    private function refusal(string $code, string $message, bool $upgrade = false): array
    {
        return ['code' => $code, 'message' => $message, 'upgrade_required' => $upgrade];
    }
}
