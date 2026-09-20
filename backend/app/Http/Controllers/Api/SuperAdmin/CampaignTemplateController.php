<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Campaign;
use App\Models\CampaignTemplate;
use App\Models\MarketingConsent;
use App\Models\WhatsAppMessage;
use App\Services\AuditLogger;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * SuperAdmin's control of what every salon is allowed to say, and oversight of
 * what they have said.
 *
 * The catalogue is central because WhatsApp makes it central: Meta approves
 * templates against the business account, and there is one account for the
 * whole platform. A salon writing its own copy is not a feature that was left
 * out — it is not a thing that can exist.
 *
 * Approving a template here does not approve it at Meta. It records that Meta
 * has approved it, by pasting in the name Meta gave it. Getting that wrong
 * means every send fails, which is why the two fields move together.
 */
class CampaignTemplateController extends Controller
{
    public function index(Request $request)
    {
        $templates = CampaignTemplate::withCount('campaigns')
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
                'meta_template_name' => $template->meta_template_name,
                'language' => $template->language,
                'min_plan' => $template->min_plan,
                'is_active' => $template->is_active,
                'campaigns_count' => $template->campaigns_count,
                // The one thing that decides whether a salon can use it.
                'sendable' => $template->is_active && $template->meta_template_name !== null,
            ]);

        return response()->json([
            'success' => true,
            'data' => $templates,
            'categories' => CampaignTemplate::CATEGORIES,
            'summary' => [
                'total' => $templates->count(),
                'sendable' => $templates->where('sendable', true)->count(),
                'awaiting_approval' => $templates->where('sendable', false)->count(),
            ],
        ]);
    }

    public function store(Request $request)
    {
        $data = $request->validate($this->rules(true));

        $template = CampaignTemplate::create($data + ['is_active' => false]);

        AuditLogger::record(
            AuditLog::CAMPAIGN_TEMPLATE_UPDATED,
            $template,
            "Added campaign template \"{$template->name}\"",
            null,
            $data,
        );

        return response()->json([
            'success' => true,
            'message' => "{$template->name} added. It cannot be used until you paste in the approved WhatsApp template name.",
            'data' => $template,
        ], 201);
    }

    public function update(Request $request, string $id)
    {
        $template = CampaignTemplate::find($id);

        if (! $template) {
            return response()->json(['success' => false, 'message' => 'Template not found.'], 404);
        }

        $data = $request->validate($this->rules(false, $template->id));

        // Switching a template on without the Meta name would put a button in
        // front of every salon that fails the moment it is pressed.
        $willBeActive = $data['is_active'] ?? $template->is_active;
        $metaName = array_key_exists('meta_template_name', $data)
            ? $data['meta_template_name']
            : $template->meta_template_name;

        if ($willBeActive && ! $metaName) {
            return response()->json([
                'success' => false,
                'message' => 'Add the approved WhatsApp template name before switching this on.',
            ], 422);
        }

        $before = $template->only(array_keys($data));
        $template->update($data);

        AuditLogger::record(
            AuditLog::CAMPAIGN_TEMPLATE_UPDATED,
            $template,
            "Edited campaign template \"{$template->name}\"",
            $before,
            $data,
        );

        return response()->json([
            'success' => true,
            'message' => 'Template updated.',
            'data' => $template->fresh(),
        ]);
    }

    /**
     * Retire a template.
     *
     * Never deleted once it has been used: the campaigns that went out through
     * it still point here, and a campaign history that cannot say what was sent
     * is not a history.
     */
    public function destroy(string $id)
    {
        $template = CampaignTemplate::withCount('campaigns')->find($id);

        if (! $template) {
            return response()->json(['success' => false, 'message' => 'Template not found.'], 404);
        }

        if ($template->campaigns_count > 0) {
            $template->update(['is_active' => false]);

            return response()->json([
                'success' => true,
                'deactivated' => true,
                'message' => sprintf(
                    '%s has been used by %d campaign(s), so it has been switched off rather than deleted. No salon will see it again.',
                    $template->name,
                    $template->campaigns_count
                ),
            ]);
        }

        $name = $template->name;
        $template->delete();

        return response()->json(['success' => true, 'deactivated' => false, 'message' => "{$name} deleted."]);
    }

    /**
     * Platform-wide marketing oversight.
     *
     * Two numbers matter more than the rest and are deliberately first: what
     * the platform is spending in messages, and how many people have asked to
     * be left alone. The second is the one that ends a WhatsApp Business
     * account if nobody is watching it.
     */
    public function overview(Request $request)
    {
        $days = (int) $request->query('days', 30);
        $since = now()->subDays($days);

        $messages = WhatsAppMessage::marketing()->where('created_at', '>=', $since);

        $topSalons = DB::table('campaigns')
            ->join('salons', 'salons.id', '=', 'campaigns.salon_id')
            ->where('campaigns.created_at', '>=', $since)
            ->whereIn('campaigns.status', ['sent', 'sending'])
            ->selectRaw('salons.name, COUNT(*) as campaigns, SUM(campaigns.sent_count) as messages')
            ->groupBy('salons.id', 'salons.name')
            ->orderByDesc('messages')
            ->limit(10)
            ->get();

        return response()->json([
            'success' => true,
            'data' => [
                'window_days' => $days,
                'campaigns' => Campaign::where('created_at', '>=', $since)->counted()->count(),
                'messages_sent' => (clone $messages)->billable()->count(),
                'messages_failed' => (clone $messages)->where('status', WhatsAppMessage::STATUS_FAILED)->count(),
                'messages_queued' => (clone $messages)->where('status', WhatsAppMessage::STATUS_QUEUED)->count(),

                'opted_out' => MarketingConsent::optedOut()->count(),
                'opted_in' => MarketingConsent::where('status', MarketingConsent::STATUS_IN)->count(),
                'opt_outs_this_window' => MarketingConsent::optedOut()
                    ->where('opted_out_at', '>=', $since)->count(),

                'top_salons' => $topSalons->map(fn ($row) => [
                    'salon' => $row->name,
                    'campaigns' => (int) $row->campaigns,
                    'messages' => (int) $row->messages,
                ]),

                // Queued marketing with no provider behind it is the signal
                // that the WhatsApp account is not actually connected.
                'provider' => config('services.whatsapp.driver'),
            ],
        ]);
    }

    private function rules(bool $creating, ?string $ignoreId = null): array
    {
        $must = fn (string $rule) => $creating ? "required|{$rule}" : "sometimes|{$rule}";

        return [
            'key' => $creating
                ? ['required', 'string', 'max:60', Rule::unique('campaign_templates', 'key')]
                : ['sometimes', 'string', 'max:60', Rule::unique('campaign_templates', 'key')->ignore($ignoreId)],
            'name' => $must('string|max:120'),
            'category' => $must('string|in:'.implode(',', array_keys(CampaignTemplate::CATEGORIES))),
            'description' => 'nullable|string|max:500',
            'body_preview' => $must('string|max:1200'),
            'variables' => 'nullable|array',
            'variables.*.key' => 'required_with:variables|string|max:60',
            'variables.*.label' => 'required_with:variables|string|max:80',
            'variables.*.example' => 'nullable|string|max:120',
            'variables.*.source' => 'required_with:variables|string|in:input,customer,salon',
            'default_audience' => 'nullable|array',
            'meta_template_name' => 'nullable|string|max:120',
            'language' => 'sometimes|string|max:10',
            'min_plan' => 'sometimes|string|in:starter,growth',
            'is_active' => 'sometimes|boolean',
            'sort_order' => 'sometimes|integer|min:0',
        ];
    }
}
