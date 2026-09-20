<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\Campaign;
use App\Models\CampaignRecipient;
use App\Models\CampaignTemplate;
use App\Models\Salon;
use App\Services\Marketing\AudienceBuilder;
use App\Services\Marketing\CampaignEntitlementService;
use App\Services\Marketing\CampaignService;
use Illuminate\Http\Request;

/**
 * WhatsApp marketing, from the salon owner's side.
 *
 * Every entitlement decision is made here rather than in the app. The plan spec
 * requires it — "plan entitlements must be controlled centrally and enforced
 * server-side" — and it is the only way that holds: an app can be old, patched
 * or simply lying about which plan it is on.
 */
class CampaignController extends Controller
{
    public function __construct(
        private CampaignService $campaigns,
        private CampaignEntitlementService $entitlements,
        private AudienceBuilder $audiences,
    ) {
    }

    /** What this salon may send, and how much of its allowance is left. */
    public function options(Request $request, string $salonId)
    {
        $salon = $this->salonFor($request, $salonId);
        $summary = $this->entitlements->summaryFor($salon);
        $plan = $this->entitlements->activeSubscription($salon)?->plan;

        $templates = CampaignTemplate::sendable()
            ->orderBy('sort_order')
            ->orderBy('name')
            ->get()
            ->map(fn (CampaignTemplate $template) => [
                'id' => $template->id,
                'key' => $template->key,
                'name' => $template->name,
                'category' => $template->category,
                'category_label' => CampaignTemplate::CATEGORIES[$template->category] ?? $template->category,
                'description' => $template->description,
                'body_preview' => $template->body_preview,
                'variables' => $template->variables ?? [],
                'default_audience' => $template->default_audience,
                // Shown but disabled rather than hidden: a Starter salon should
                // see what Growth would give it, which is the upgrade prompt
                // the spec asks for.
                'locked' => $template->requiresGrowth() && ! ($plan->has_customer_segmentation ?? false),
                'min_plan' => $template->min_plan,
            ]);

        $segments = collect($this->audiences->catalogue())->map(fn (array $segment) => $segment + [
            'locked' => ! $this->audiences->isAllowed($segment['key'], $plan),
        ]);

        return response()->json([
            'success' => true,
            'entitlement' => $summary,
            'templates' => $templates,
            'segments' => $segments,
        ]);
    }

    /**
     * How many people an audience would reach, before committing to it.
     *
     * Costs nothing and spends no allowance, so the app can call it on every
     * change to the filters.
     */
    public function preview(Request $request, string $salonId)
    {
        $salon = $this->salonFor($request, $salonId);

        $data = $request->validate([
            'audience' => 'required|array',
            'audience.segment' => 'required|string',
            'audience.service_id' => 'nullable|uuid',
            'audience.combo_id' => 'nullable|uuid',
            'audience.sub_area_id' => 'nullable|uuid',
            'audience.days' => 'nullable|integer|min:1|max:730',
            'audience.visits' => 'nullable|integer|min:1|max:100',
            'audience.min_spend' => 'nullable|numeric|min:0',
            'audience.birthday_window' => 'nullable|integer|min:0|max:60',
        ]);

        if ($refusal = $this->segmentRefusal($salon, $data['audience']['segment'])) {
            return response()->json(['success' => false] + $refusal, 403);
        }

        return response()->json([
            'success' => true,
            'preview' => $this->campaigns->preview($salon, $data['audience']),
        ]);
    }

    public function index(Request $request, string $salonId)
    {
        $salon = $this->salonFor($request, $salonId);

        $campaigns = Campaign::with('template:id,name,category')
            ->where('salon_id', $salon->id)
            ->orderByDesc('created_at')
            ->paginate(20);

        return response()->json([
            'success' => true,
            'entitlement' => $this->entitlements->summaryFor($salon),
            'data' => $campaigns->through(fn (Campaign $campaign) => $this->summarise($campaign)),
        ]);
    }

    public function show(Request $request, string $salonId, string $id)
    {
        $salon = $this->salonFor($request, $salonId);

        $campaign = Campaign::with('template')
            ->where('salon_id', $salon->id)
            ->findOrFail($id);

        // Only the ones worth looking at. A salon does not need two thousand
        // delivered rows, it needs the ones that did not work.
        $problems = CampaignRecipient::where('campaign_id', $campaign->id)
            ->whereIn('status', [CampaignRecipient::STATUS_SKIPPED, CampaignRecipient::STATUS_FAILED])
            ->limit(100)
            ->get()
            ->map(fn (CampaignRecipient $r) => [
                'name' => $r->name,
                'status' => $r->status,
                'reason' => $r->skipLabel(),
            ]);

        return response()->json([
            'success' => true,
            'data' => $this->summarise($campaign) + [
                'preview_text' => $campaign->template?->renderPreview(
                    ($campaign->variables ?? []) + ['customer_name' => 'Priya', 'salon_name' => $salon->name]
                ),
                'audience' => $campaign->audience,
                'problems' => $problems,
            ],
        ]);
    }

    /**
     * Create and, unless it is being kept as a draft, send.
     *
     * One endpoint rather than create-then-send because the audience is
     * recounted at dispatch anyway; splitting them would invite a salon to
     * approve a preview on Monday and send it on Friday to a different list.
     */
    public function store(Request $request, string $salonId)
    {
        $salon = $this->salonFor($request, $salonId);

        $data = $request->validate([
            'campaign_template_id' => 'required|uuid|exists:campaign_templates,id',
            'name' => 'required|string|max:120',
            'audience' => 'required|array',
            'audience.segment' => 'required|string',
            'variables' => 'nullable|array',
            'scheduled_for' => 'nullable|date|after:now',
            'send_now' => 'sometimes|boolean',
        ]);

        $template = CampaignTemplate::findOrFail($data['campaign_template_id']);

        if ($refusal = $this->segmentRefusal($salon, $data['audience']['segment'])) {
            return response()->json(['success' => false] + $refusal, 403);
        }

        $preview = $this->campaigns->preview($salon, $data['audience']);

        $refusal = $this->entitlements->refusalFor($salon, $template, $preview['will_send']);

        if ($refusal) {
            return response()->json(['success' => false] + $refusal, 403);
        }

        $campaign = $this->campaigns->create(
            salon: $salon,
            template: $template,
            name: $data['name'],
            audience: $data['audience'],
            variables: $data['variables'] ?? [],
            userId: $request->user()?->id,
            scheduledFor: $data['scheduled_for'] ?? null,
        );

        if ($request->boolean('send_now', true) || ! empty($data['scheduled_for'])) {
            $campaign = $this->campaigns->launch($campaign);
        }

        return response()->json([
            'success' => true,
            'message' => $campaign->status === Campaign::STATUS_SCHEDULED
                ? 'Scheduled. It will go out at '.$campaign->scheduled_for->format('g:ia \o\n j M').'.'
                : 'Your campaign is on its way.',
            'data' => $this->summarise($campaign),
        ], 201);
    }

    /** Stop a campaign that has not gone out yet. */
    public function cancel(Request $request, string $salonId, string $id)
    {
        $salon = $this->salonFor($request, $salonId);
        $campaign = Campaign::where('salon_id', $salon->id)->findOrFail($id);

        if (! $campaign->isEditable()) {
            return response()->json([
                'success' => false,
                'message' => 'This campaign has already started going out and cannot be stopped.',
            ], 422);
        }

        $campaign->update(['status' => Campaign::STATUS_CANCELLED, 'completed_at' => now()]);

        return response()->json(['success' => true, 'message' => 'Campaign cancelled.']);
    }

    /** @return array<string, mixed> */
    private function summarise(Campaign $campaign): array
    {
        return [
            'id' => $campaign->id,
            'name' => $campaign->name,
            'status' => $campaign->status,
            'template' => $campaign->template?->name,
            'category' => $campaign->template?->category,
            'recipients_count' => $campaign->recipients_count,
            'sent_count' => $campaign->sent_count,
            'delivered_count' => $campaign->delivered_count,
            'read_count' => $campaign->read_count,
            'failed_count' => $campaign->failed_count,
            'skipped_count' => $campaign->skipped_count,
            'delivery_rate' => $campaign->deliveryRate(),
            'read_rate' => $campaign->readRate(),
            'scheduled_for' => $campaign->scheduled_for?->toIso8601String(),
            'created_at' => $campaign->created_at?->toIso8601String(),
            'completed_at' => $campaign->completed_at?->toIso8601String(),
            'failure_reason' => $campaign->failure_reason,
        ];
    }

    private function segmentRefusal(Salon $salon, string $segment): ?array
    {
        $plan = $this->entitlements->activeSubscription($salon)?->plan;

        if ($this->audiences->isAllowed($segment, $plan)) {
            return null;
        }

        return [
            'code' => 'upgrade_required',
            'message' => 'Targeting this group is part of the Growth plan.',
            'upgrade_required' => true,
        ];
    }

    /** The salon must belong to whoever is asking. */
    private function salonFor(Request $request, string $salonId): Salon
    {
        return Salon::where('admin_id', $request->user()->id)->findOrFail($salonId);
    }
}
