<?php

namespace App\Services\Marketing;

use App\Jobs\DispatchCampaignJob;
use App\Models\Campaign;
use App\Models\CampaignRecipient;
use App\Models\CampaignTemplate;
use App\Models\Salon;
use Illuminate\Support\Facades\DB;

/**
 * Creating, previewing and launching a campaign.
 *
 * The preview and the send deliberately share one audience-building path. A
 * preview that counts differently from the send is worse than no preview: the
 * salon approves one number and a different one goes out.
 */
class CampaignService
{
    public function __construct(
        private AudienceBuilder $audiences,
        private CampaignEntitlementService $entitlements,
        private MarketingSettings $settings,
    ) {
    }

    /**
     * What would happen if this were sent now.
     *
     * @return array<string, mixed>
     */
    public function preview(Salon $salon, array $audience): array
    {
        $rows = $this->audiences->build($salon, $audience);
        $screened = $this->audiences->screenForConsent($rows);

        $reachable = $screened['reachable'];
        $messagesLeft = $this->entitlements->messagesRemaining($salon);
        $dailyLeft = $this->entitlements->dailyRemaining($salon);

        // The binding constraint, whichever it is.
        $cap = collect([$messagesLeft, $dailyLeft])->filter(fn ($v) => $v !== null)->min();
        $willSend = $cap === null ? $reachable->count() : min($reachable->count(), $cap);

        return [
            'matched' => $rows->count(),
            'reachable' => $reachable->count(),
            'will_send' => $willSend,
            'beyond_allowance' => max(0, $reachable->count() - $willSend),
            'skipped' => $screened['skipped'],
            'sample' => $reachable->take(5)->map(fn ($row) => [
                'name' => $row->name,
                'phone' => $this->maskPhone($row->phone),
                'visits' => (int) $row->visits,
            ])->values(),
        ];
    }

    /** A campaign in draft. Nothing is sent and no allowance is spent yet. */
    public function create(
        Salon $salon,
        CampaignTemplate $template,
        string $name,
        array $audience,
        array $variables,
        ?string $userId,
        ?string $scheduledFor = null,
    ): Campaign {
        return Campaign::create([
            'salon_id' => $salon->id,
            'campaign_template_id' => $template->id,
            'created_by' => $userId,
            'name' => $name,
            'status' => Campaign::STATUS_DRAFT,
            'audience' => $audience,
            'variables' => $variables,
            'scheduled_for' => $scheduledFor,
        ]);
    }

    /**
     * Commit a campaign: stamp the billing cycle it is charged to, then hand it
     * to the queue.
     *
     * The cycle is written here rather than when the recipients are built,
     * because this is the moment the salon spends the allowance — a job that
     * runs an hour later, possibly after a renewal, must still be charged to
     * the cycle the salon was in when it pressed send.
     */
    public function launch(Campaign $campaign): Campaign
    {
        $salon = $campaign->salon;
        $subscription = $this->entitlements->activeSubscription($salon);

        if ($subscription) {
            [$start, $end] = $this->entitlements->cycleFor($subscription);
            $campaign->cycle_start = $start;
            $campaign->cycle_end = $end;
        }

        // Quiet hours are not a refusal; the send simply waits for a civil hour.
        $scheduled = $campaign->scheduled_for;
        $earliest = $this->settings->nextSendableTime();

        if (! $scheduled && $earliest->greaterThan(now())) {
            $campaign->scheduled_for = $earliest;
        }

        $campaign->status = $campaign->scheduled_for && $campaign->scheduled_for->isFuture()
            ? Campaign::STATUS_SCHEDULED
            : Campaign::STATUS_SENDING;

        $campaign->save();

        $job = DispatchCampaignJob::dispatch($campaign->id);

        if ($campaign->status === Campaign::STATUS_SCHEDULED) {
            $job->delay($campaign->scheduled_for);
        }

        return $campaign->fresh();
    }

    /**
     * Turn the audience into recipient rows.
     *
     * Everything the audience matched is written down, including the people who
     * will not be messaged and why. A salon asking "it said 240, why did 180 go
     * out" deserves an answer, and this is where it comes from.
     */
    public function materialiseRecipients(Campaign $campaign): int
    {
        $salon = $campaign->salon;
        $rows = $this->audiences->build($salon, $campaign->audience ?? []);
        $screened = $this->audiences->screenForConsent($rows);

        $messagesLeft = $this->entitlements->messagesRemaining($salon);
        $dailyLeft = $this->entitlements->dailyRemaining($salon);
        $allowed = collect([$messagesLeft, $dailyLeft])->filter(fn ($v) => $v !== null)->min();

        $reachablePhones = $screened['reachable']->pluck('phone')->flip();
        $sendable = 0;
        $counts = ['skipped' => 0];

        DB::transaction(function () use ($campaign, $rows, $reachablePhones, $allowed, &$sendable, &$counts, $messagesLeft, $dailyLeft) {
            foreach ($rows as $row) {
                $isReachable = $reachablePhones->has($row->phone);

                $status = CampaignRecipient::STATUS_SKIPPED;
                $skipReason = $row->skip_reason ?? CampaignRecipient::SKIP_NO_CONSENT;

                if ($isReachable) {
                    if ($allowed !== null && $sendable >= $allowed) {
                        // Which allowance ran out changes the advice the salon
                        // gets, so the two are not collapsed into one reason.
                        $skipReason = ($dailyLeft !== null && $dailyLeft <= $sendable)
                            ? CampaignRecipient::SKIP_DAILY_CAP
                            : CampaignRecipient::SKIP_OVER_QUOTA;
                    } else {
                        $status = CampaignRecipient::STATUS_PENDING;
                        $skipReason = null;
                        $sendable++;
                    }
                }

                if ($status === CampaignRecipient::STATUS_SKIPPED) {
                    $counts['skipped']++;
                }

                CampaignRecipient::updateOrCreate(
                    ['campaign_id' => $campaign->id, 'phone' => $row->phone],
                    [
                        'user_id' => $row->user_id,
                        'name' => $row->name,
                        'status' => $status,
                        'skip_reason' => $skipReason,
                        'variables' => $this->variablesFor($campaign, $row),
                    ]
                );
            }

            $campaign->update([
                'recipients_count' => $rows->count(),
                'skipped_count' => $counts['skipped'],
            ]);
        });

        return $sendable;
    }

    /**
     * The values this template's placeholders take for one person.
     *
     * Salon-level values come from the campaign; anything named like a customer
     * field is filled per recipient, which is what makes "Hi Priya" possible.
     */
    private function variablesFor(Campaign $campaign, object $row): array
    {
        $values = $campaign->variables ?? [];

        $values['customer_name'] = $row->name ?: 'there';
        $values['salon_name'] = $campaign->salon->name ?? '';

        return $values;
    }

    private function maskPhone(string $phone): string
    {
        return strlen($phone) <= 4 ? $phone : str_repeat('•', strlen($phone) - 4).substr($phone, -4);
    }
}
