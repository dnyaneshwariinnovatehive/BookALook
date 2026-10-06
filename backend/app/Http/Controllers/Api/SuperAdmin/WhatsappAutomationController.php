<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\WhatsappAutomation;
use App\Models\WhatsAppMessage;
use App\Services\Notifications\WhatsappVariableCatalog;
use App\Jobs\SendWhatsAppMessageJob;
use Carbon\Carbon;
use Illuminate\Http\Request;

class WhatsappAutomationController extends Controller
{
    public function index()
    {
        $automations = WhatsappAutomation::all()->map(function ($automation) {
            return $this->formatAutomation($automation);
        });

        // Ensure we sort them in a logical order
        $order = [
            'whatsapp_otp',
            'whatsapp_customer_birthday',
            'whatsapp_25_day_reminder',
            'whatsapp_appointment_reminder'
        ];

        $sortedAutomations = $automations->sortBy(function ($model) use ($order) {
            return array_search($model['key'], $order);
        })->values();

        return response()->json([
            'success' => true,
            'data' => $sortedAutomations,
        ]);
    }

    public function update(Request $request, string $key)
    {
        $automation = WhatsappAutomation::where('key', $key)->firstOrFail();

        $data = $request->validate([
            'is_enabled' => 'sometimes|boolean',
            'aisensy_campaign_name' => 'nullable|string|max:120',
            'lead_time_minutes' => 'nullable|integer|min:1|max:43200',
        ]);

        if (isset($data['is_enabled']) && $data['is_enabled']) {
            if ($automation->key === 'whatsapp_otp') {
                return response()->json([
                    'success' => false,
                    'message' => 'WhatsApp OTP is currently disabled during development.',
                ], 422);
            }

            $campaign = $data['aisensy_campaign_name'] ?? $automation->aisensy_campaign_name;
            if (empty($campaign)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Configure an AiSensy campaign before enabling this automation.',
                ], 422);
            }
        }

        $automation->update($data);

        return response()->json([
            'success' => true,
            'message' => 'Automation updated successfully.',
            'data' => $this->formatAutomation($automation->fresh()),
        ]);
    }

    public function test(Request $request, string $key)
    {
        $automation = WhatsappAutomation::where('key', $key)->firstOrFail();

        $request->validate([
            'phone' => 'required|string|max:20',
        ]);

        if (empty($automation->aisensy_campaign_name)) {
            return response()->json([
                'success' => false,
                'message' => 'Cannot send test message: AiSensy campaign is not configured.',
            ], 422);
        }

        // Generate sample variables for the payload based on the catalog
        $variables = WhatsappVariableCatalog::forAutomation($automation->key);
        $payloadParams = [];
        foreach ($variables as $variable) {
            $payloadParams[] = $variable['example'] ?? 'Test';
        }

        $message = WhatsAppMessage::create([
            'to_phone' => $request->phone,
            'template' => 'test_' . $automation->key,
            'campaign' => $automation->aisensy_campaign_name,
            'payload' => ['parameters' => $payloadParams],
            'status' => WhatsAppMessage::STATUS_QUEUED,
            'category' => 'test', // Explicitly marked as test
        ]);

        // Dispatch synchronously or just let the queue handle it, but wait to give immediate feedback.
        // Usually, testing sends we want to dispatch and let it queue.
        SendWhatsAppMessageJob::dispatchSync($message->id);

        $message->refresh();

        if ($message->status === WhatsAppMessage::STATUS_FAILED) {
            return response()->json([
                'success' => false,
                'message' => 'Test message failed to send: ' . $message->error,
            ], 400);
        }

        return response()->json([
            'success' => true,
            'message' => 'Test message sent successfully.',
        ]);
    }

    private function formatAutomation(WhatsappAutomation $automation)
    {
        return [
            'id' => $automation->id,
            'key' => $automation->key,
            'name' => $automation->name,
            'description' => $automation->description,
            'audience' => $automation->audience,
            'frequency_label' => $automation->frequency_label,
            'is_enabled' => $automation->is_enabled,
            'aisensy_campaign_name' => $automation->aisensy_campaign_name,
            'lead_time_minutes' => $automation->lead_time_minutes,
            'variables' => WhatsappVariableCatalog::forAutomation($automation->key),
            'health' => $this->computeHealth($automation),
        ];
    }

    private function computeHealth(WhatsappAutomation $automation): array
    {
        if (! $automation->is_enabled) {
            return [
                'status' => 'DISABLED',
                'last_run_at' => null,
                'last_success_at' => null,
                'last_failure_at' => null,
            ];
        }

        if (empty($automation->aisensy_campaign_name)) {
            return [
                'status' => 'NOT_CONFIGURED',
                'last_run_at' => null,
                'last_success_at' => null,
                'last_failure_at' => null,
            ];
        }

        // Get recent non-test messages for this campaign
        $recentMessages = WhatsAppMessage::where('campaign', $automation->aisensy_campaign_name)
            ->where(function($q) {
                $q->whereNull('category')->orWhere('category', '!=', 'test');
            })
            ->orderBy('created_at', 'desc')
            ->limit(20)
            ->get();

        if ($recentMessages->isEmpty()) {
            return [
                'status' => 'READY',
                'last_run_at' => null,
                'last_success_at' => null,
                'last_failure_at' => null,
            ];
        }

        $failedCount = $recentMessages->where('status', WhatsAppMessage::STATUS_FAILED)->count();
        $totalCount = $recentMessages->count();

        $lastSuccess = $recentMessages->where('status', WhatsAppMessage::STATUS_SENT)->first();
        $lastFailure = $recentMessages->where('status', WhatsAppMessage::STATUS_FAILED)->first();

        $status = 'WORKING';
        if ($failedCount === $totalCount) {
            $status = 'FAILING';
        } elseif ($failedCount > 0) {
            $status = 'NEEDS_ATTENTION';
        }

        return [
            'status' => $status,
            'last_run_at' => $recentMessages->first()->created_at,
            'last_success_at' => $lastSuccess?->created_at,
            'last_failure_at' => $lastFailure?->created_at,
            'recent_success_count' => $totalCount - $failedCount,
            'recent_failure_count' => $failedCount,
        ];
    }
}
