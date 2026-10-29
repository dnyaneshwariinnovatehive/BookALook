<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Console\Commands\EnforceCommissionDues;
use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Salon;
use App\Services\AuditLogger;
use App\Services\CommissionDuesService;
use App\Services\Notifications\NotificationService;
use App\Services\PayoutService;
use App\Support\Notifications\NotificationType;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Commission Model salons that owe BookALook, and what SuperAdmin can do
 * about one: push its due date out, pause the steps, apply a step by hand,
 * send a reminder, or record a payment made outside the app.
 */
class CommissionDuesController extends Controller
{
    public function __construct(private CommissionDuesService $dues)
    {
    }

    public function index(Request $request)
    {
        $settings = $this->dues->settings();

        $rows = Salon::with(['city:id,name', 'admin:id,name,phone'])
            ->where('commission_opt_in', true)
            ->whereIn('status', ['active', 'suspended'])
            ->get()
            ->map(fn (Salon $salon) => $this->row($salon, $settings))
            ->filter(fn ($row) => $row['state']['applies'] || $row['state']['under_review'] > 0)
            ->sortByDesc(fn ($row) => [$row['state']['days_overdue'] ?? -999, $row['state']['owed']])
            ->values();

        $stageCounts = collect(CommissionDuesService::STEPS)
            ->mapWithKeys(fn ($step) => [$step => $rows->where('state.stage', $step)->count()]);

        return response()->json([
            'success' => true,
            'data' => $rows,
            'summary' => [
                'salons' => $rows->where('state.applies', true)->count(),
                'owed' => round($rows->sum('state.owed'), 2),
                'overdue' => $rows->filter(fn ($r) => ($r['state']['days_overdue'] ?? -1) >= 0)->count(),
                'under_review' => $rows->sum('state.under_review'),
                'by_stage' => $stageCounts,
            ],
            'settings' => $settings,
            'labels' => CommissionDuesService::LABELS,
        ]);
    }

    public function extend(Request $request, string $salonId)
    {
        $data = $request->validate([
            'until' => 'required|date|after:today',
            'reason' => 'required|string|min:3|max:500',
        ]);
        $salon = $this->commissionSalon($salonId);

        $salon->forceFill([
            'dues_extended_until' => Carbon::parse($data['until'])->toDateString(),
            'dues_override_reason' => $data['reason'],
        ])->save();

        $this->tellOwner($salon, 'Commission due date extended',
            'BookALook has moved your commission due date to ' . Carbon::parse($data['until'])->format('j M Y') . '.');

        return $this->changed($request, $salon, 'Extended the due date to ' . Carbon::parse($data['until'])->format('j M Y'), $data['reason']);
    }

    public function pause(Request $request, string $salonId)
    {
        $data = $request->validate([
            'paused' => 'required|boolean',
            'reason' => 'nullable|string|max:500',
        ]);
        $salon = $this->commissionSalon($salonId);

        $salon->forceFill([
            'dues_paused' => $data['paused'],
            'dues_override_reason' => $data['reason'] ?? $salon->dues_override_reason,
        ])->save();

        return $this->changed($request, $salon, $data['paused'] ? 'Paused dues steps' : 'Resumed dues steps', $data['reason'] ?? null);
    }

    public function stage(Request $request, string $salonId)
    {
        $data = $request->validate([
            // automatic = back to the schedule.
            'stage' => ['required', Rule::in(array_merge(['automatic', CommissionDuesService::OVERRIDE_NONE], CommissionDuesService::STEPS))],
            'reason' => 'nullable|string|max:500',
        ]);
        $salon = $this->commissionSalon($salonId);
        $override = $data['stage'] === 'automatic' ? null : $data['stage'];

        $salon->forceFill([
            'dues_stage_override' => $override,
            'dues_override_reason' => $data['reason'] ?? $salon->dues_override_reason,
        ])->save();

        $state = $this->dues->state($salon->fresh());
        if ($state['stage'] && $state['stage'] !== CommissionDuesService::STEP_REMINDER) {
            $this->tellOwner($salon, CommissionDuesService::LABELS[$state['stage']],
                CommissionDuesService::stepMessage($state['stage'], $state['owed']));
        }

        $label = match ($data['stage']) {
            'automatic' => 'Returned dues steps to the schedule',
            CommissionDuesService::OVERRIDE_NONE => 'Lifted every dues step',
            default => 'Applied dues step: ' . CommissionDuesService::LABELS[$data['stage']],
        };

        return $this->changed($request, $salon, $label, $data['reason'] ?? null);
    }

    public function remind(Request $request, string $salonId, NotificationService $notifications)
    {
        $salon = $this->commissionSalon($salonId);
        $state = $this->dues->state($salon);

        if (! $state['applies']) {
            return response()->json(['success' => false, 'message' => 'This salon owes nothing right now.'], 422);
        }

        app(EnforceCommissionDues::class)->remind($salon, $state, $notifications, manual: true);

        return response()->json(['success' => true, 'message' => 'Reminder sent to the owner.']);
    }

    /** Money received outside the app: settles every payout the salon owes on. */
    public function recordPayment(Request $request, string $salonId, PayoutService $payouts)
    {
        $data = $request->validate([
            'reference' => 'required|string|max:120',
            'note' => 'nullable|string|max:500',
        ]);
        $salon = $this->commissionSalon($salonId);
        $owed = $this->dues->owedPayouts($salon->id);

        if ($owed->isEmpty()) {
            return response()->json(['success' => false, 'message' => 'This salon owes nothing right now.'], 422);
        }

        $total = 0.0;
        foreach ($owed as $payout) {
            $total += abs((float) $payout->net_amount);
            $payouts->markDistributed($payout, $request->user(), $data['reference'], $data['note'] ?? 'Paid outside the app; recorded by SuperAdmin.');
        }

        $this->tellOwner($salon, 'Payment received',
            'BookALook has recorded your payment of ₹' . number_format($total, 2) . '. Thank you!');

        AuditLogger::record(
            action: AuditLog::COMMISSION_DUES_PAYMENT,
            entity: $salon,
            label: $salon->name,
            after: ['amount' => round($total, 2), 'payouts' => $owed->count(), 'reference' => $data['reference']],
            metadata: ['salon_id' => $salon->id],
        );

        return response()->json([
            'success' => true,
            'message' => 'Payment of ₹' . number_format($total, 2) . ' recorded. Every step is lifted.',
            'row' => $this->row($salon->fresh(['city', 'admin'])),
        ]);
    }

    // ------------------------------------------------------------- internals

    private function row(Salon $salon, ?array $settings = null): array
    {
        $state = $this->dues->state($salon, $settings);

        return [
            'salon' => [
                'id' => $salon->id,
                'name' => $salon->name,
                'city' => $salon->city?->name,
                'status' => $salon->status,
                'owner' => $salon->admin ? ['name' => $salon->admin->name, 'phone' => $salon->admin->phone] : null,
                'commission_percentage' => (float) ($salon->commission_percentage ?? 0),
            ],
            'state' => $state,
            'last_reminded_at' => $salon->dues_last_reminded_at?->toIso8601String(),
        ];
    }

    private function commissionSalon(string $salonId): Salon
    {
        $salon = Salon::with(['city:id,name', 'admin:id,name,phone'])->findOrFail($salonId);

        abort_unless($salon->isOnCommissionModel(), 422, 'This salon is not on the Commission Model.');

        return $salon;
    }

    private function changed(Request $request, Salon $salon, string $what, ?string $reason)
    {
        AuditLogger::record(
            action: AuditLog::COMMISSION_DUES_CHANGED,
            entity: $salon,
            label: "{$salon->name}: {$what}",
            after: [
                'extended_until' => $salon->dues_extended_until ? Carbon::parse($salon->dues_extended_until)->toDateString() : null,
                'paused' => (bool) $salon->dues_paused,
                'stage_override' => $salon->dues_stage_override,
            ],
            metadata: ['salon_id' => $salon->id, 'reason' => $reason],
        );

        return response()->json([
            'success' => true,
            'message' => $what . '.',
            'row' => $this->row($salon->fresh(['city', 'admin'])),
        ]);
    }

    private function tellOwner(Salon $salon, string $title, string $message): void
    {
        app(NotificationService::class)->send(
            recipient: $salon->admin_id,
            type: NotificationType::GENERAL,
            title: "{$title} · {$salon->name}",
            message: $message,
            data: ['action' => 'commission_dues', 'salon_id' => $salon->id],
            salon: $salon,
        );
    }
}
