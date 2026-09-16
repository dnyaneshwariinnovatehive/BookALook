<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Complaint;
use App\Models\Notification;
use App\Models\Review;
use App\Models\Salon;
use App\Services\AuditLogger;
use App\Services\ReviewService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Complaints, and the two things SuperAdmin can do about one.
 *
 * A warning is a message on the record: the owner reads it in their app, and it
 * stays attached to the complaint so a pattern of them is visible later. A
 * suspension takes the salon offline immediately — customers stop seeing it and
 * the owner's own app locks, which SalonAccessService already enforces off
 * salons.status.
 *
 * Both are deliberate, written acts. Neither happens without a reason typed by
 * a person, because the salon is told what it was.
 */
class ComplaintController extends Controller
{
    public function __construct(private ReviewService $reviews)
    {
    }

    /**
     * The queue. Outstanding first, because those are the ones that need a
     * decision — a resolved complaint is history.
     */
    public function index(Request $request)
    {
        $request->validate([
            'status' => 'nullable|in:open,under_review,resolved,dismissed,outstanding',
            'salon_id' => 'nullable|uuid',
        ]);

        $query = Complaint::with([
            'salon:id,name,status,admin_id',
            'salon.admin:id,name,phone',
            'customer:id,name,phone',
            'appointment:id,appointment_date,start_time',
            'resolver:id,name',
        ]);

        if ($request->status === 'outstanding') {
            $query->outstanding();
        } elseif ($request->filled('status')) {
            $query->where('status', $request->status);
        }

        if ($request->filled('salon_id')) {
            $query->where('salon_id', $request->salon_id);
        }

        $complaints = $query
            ->orderByRaw("case when status in ('open','under_review') then 0 else 1 end")
            ->orderByDesc('created_at')
            ->get();

        return response()->json([
            'success' => true,
            'counts' => [
                'outstanding' => Complaint::outstanding()->count(),
                'open' => Complaint::where('status', Complaint::STATUS_OPEN)->count(),
                'resolved' => Complaint::where('status', Complaint::STATUS_RESOLVED)->count(),
                'dismissed' => Complaint::where('status', Complaint::STATUS_DISMISSED)->count(),
            ],
            'data' => $complaints->map(fn (Complaint $c) => $this->present($c)),
        ]);
    }

    /**
     * One complaint with the context needed to judge it.
     *
     * A single angry customer and a salon with a run of one-star reviews are
     * different situations, so the salon's rating and its complaint history
     * come with it. Deciding to suspend a business on one report alone would be
     * a mistake the interface should not make easy.
     */
    public function show(string $id)
    {
        $complaint = Complaint::with([
            'salon:id,name,status,admin_id,suspended_reason',
            'salon.admin:id,name,phone,email',
            'customer:id,name,phone',
            'appointment:id,appointment_date,start_time,total_amount',
            'resolver:id,name',
        ])->find($id);

        if (! $complaint) {
            return response()->json(['success' => false, 'message' => 'Complaint not found.'], 404);
        }

        $salonId = $complaint->salon_id;

        return response()->json([
            'success' => true,
            'data' => $this->present($complaint) + [
                'description' => $complaint->description,
            ],
            'salon_context' => [
                'rating' => $this->reviews->summaryFor($salonId),
                'complaints_total' => Complaint::where('salon_id', $salonId)->count(),
                'complaints_outstanding' => Complaint::where('salon_id', $salonId)->outstanding()->count(),
                'warnings_sent' => Complaint::where('salon_id', $salonId)
                    ->where('action_taken', Complaint::ACTION_WARNING)->count(),
                // What the customer publicly said about this same visit, if
                // anything. A five-star review beside an angry complaint is
                // worth knowing about.
                'review_for_this_visit' => $this->reviewForVisit($complaint),
            ],
        ]);
    }

    /** @return array<string, mixed>|null */
    private function reviewForVisit(Complaint $complaint): ?array
    {
        if (! $complaint->related_appointment_id) {
            return null;
        }

        $review = Review::where('appointment_id', $complaint->related_appointment_id)->first();

        return $review ? ['rating' => $review->rating, 'comment' => $review->comment] : null;
    }

    /**
     * Send the salon's owner a written warning.
     *
     * Nothing about the salon changes — it keeps trading. What changes is that
     * the owner has been told, in writing, and the platform can prove it.
     */
    public function warn(Request $request, string $id)
    {
        $data = $request->validate([
            'message' => 'required|string|max:1000',
        ]);

        $complaint = Complaint::with('salon')->find($id);

        if (! $complaint) {
            return response()->json(['success' => false, 'message' => 'Complaint not found.'], 404);
        }

        DB::transaction(function () use ($complaint, $data, $request) {
            $this->notifyOwner(
                $complaint,
                'A warning from BookALook',
                $data['message'],
                'complaint_warning'
            );

            $complaint->update([
                'status' => Complaint::STATUS_RESOLVED,
                'action_taken' => Complaint::ACTION_WARNING,
                'resolution_note' => $data['message'],
                'resolved_by' => $request->user()->id,
                'resolved_at' => now(),
            ]);

            AuditLogger::record(
                action: AuditLog::COMPLAINT_WARNING_SENT,
                entity: $complaint->salon,
                label: $complaint->salon->name ?? 'Salon',
                metadata: [
                    'reason' => $data['message'],
                    'complaint_id' => $complaint->id,
                    'complaint_subject' => $complaint->subject,
                ],
            );
        });

        return response()->json([
            'success' => true,
            'message' => "Warning sent to {$complaint->salon->name}.",
            'data' => $this->present($complaint->fresh(['salon', 'customer', 'resolver'])),
        ]);
    }

    /**
     * Take the salon offline.
     *
     * Immediate and total: customers stop seeing it, its owner and staff lose
     * the app. The reason is stored on the salon itself because that is what
     * every locked screen reads from, and it is sent to the owner so they are
     * not left guessing why their business disappeared.
     */
    public function suspend(Request $request, string $id)
    {
        $data = $request->validate([
            'reason' => 'required|string|max:1000',
        ]);

        $complaint = Complaint::with('salon')->find($id);

        if (! $complaint) {
            return response()->json(['success' => false, 'message' => 'Complaint not found.'], 404);
        }

        $previousStatus = $complaint->salon?->status;

        DB::transaction(function () use ($complaint, $data, $request, $previousStatus) {
            Salon::where('id', $complaint->salon_id)->update([
                'status' => 'suspended',
                'suspended_reason' => $data['reason'],
            ]);

            $this->notifyOwner(
                $complaint,
                'Your salon has been suspended',
                $data['reason'],
                'salon_suspended'
            );

            $complaint->update([
                'status' => Complaint::STATUS_RESOLVED,
                'action_taken' => Complaint::ACTION_SUSPENDED,
                'resolution_note' => $data['reason'],
                'resolved_by' => $request->user()->id,
                'resolved_at' => now(),
            ]);

            // The heaviest thing SuperAdmin can do to a business, so it is the
            // entry that most needs to be attributable afterwards.
            AuditLogger::record(
                action: AuditLog::SALON_SUSPENDED,
                entity: $complaint->salon,
                label: $complaint->salon->name ?? 'Salon',
                before: ['status' => $previousStatus],
                after: ['status' => 'suspended'],
                metadata: [
                    'reason' => $data['reason'],
                    'complaint_id' => $complaint->id,
                    'complaint_subject' => $complaint->subject,
                ],
            );
        });

        return response()->json([
            'success' => true,
            'message' => "{$complaint->salon->name} has been suspended and the owner told why.",
            'data' => $this->present($complaint->fresh(['salon', 'customer', 'resolver'])),
        ]);
    }

    /**
     * Lift a suspension. Separate from the complaint queue on purpose — putting
     * a salon back online is not "resolving" anything, it is undoing.
     */
    public function reinstate(Request $request, string $salonId)
    {
        $salon = Salon::find($salonId);

        if (! $salon) {
            return response()->json(['success' => false, 'message' => 'Salon not found.'], 404);
        }

        if ($salon->status !== 'suspended') {
            return response()->json([
                'success' => false,
                'message' => 'That salon is not suspended.',
            ], 422);
        }

        $previousReason = $salon->suspended_reason;
        $salon->update(['status' => 'active', 'suspended_reason' => null]);

        AuditLogger::record(
            action: AuditLog::SALON_REINSTATED,
            entity: $salon,
            label: $salon->name,
            before: ['status' => 'suspended'],
            after: ['status' => 'active'],
            metadata: ['lifted_suspension_for' => $previousReason],
        );

        if ($salon->admin_id) {
            Notification::create([
                'user_id' => $salon->admin_id,
                'type' => 'salon_reinstated',
                'title' => 'Your salon is back online',
                'message' => "{$salon->name} is live again and can take bookings.",
                'data' => ['salon_id' => $salon->id],
                'related_salon_id' => $salon->id,
                'is_read' => false,
            ]);
        }

        return response()->json([
            'success' => true,
            'message' => "{$salon->name} is back online.",
        ]);
    }

    /**
     * Close a complaint without acting on it.
     */
    public function dismiss(Request $request, string $id)
    {
        $data = $request->validate([
            'note' => 'nullable|string|max:1000',
        ]);

        $complaint = Complaint::find($id);

        if (! $complaint) {
            return response()->json(['success' => false, 'message' => 'Complaint not found.'], 404);
        }

        $complaint->update([
            'status' => Complaint::STATUS_DISMISSED,
            'action_taken' => Complaint::ACTION_DISMISSED,
            'resolution_note' => $data['note'] ?? null,
            'resolved_by' => $request->user()->id,
            'resolved_at' => now(),
        ]);

        AuditLogger::record(
            action: AuditLog::COMPLAINT_DISMISSED,
            entity: $complaint->salon,
            label: $complaint->salon->name ?? 'Salon',
            metadata: [
                'reason' => $data['note'] ?? null,
                'complaint_id' => $complaint->id,
                'complaint_subject' => $complaint->subject,
            ],
        );

        return response()->json([
            'success' => true,
            'message' => 'Complaint dismissed.',
            'data' => $this->present($complaint->fresh(['salon', 'customer', 'resolver'])),
        ]);
    }

    private function notifyOwner(Complaint $complaint, string $title, string $message, string $type): void
    {
        if (! $complaint->salon?->admin_id) {
            return;
        }

        Notification::create([
            'user_id' => $complaint->salon->admin_id,
            'type' => $type,
            'title' => $title,
            'message' => $message,
            'data' => [
                'complaint_id' => $complaint->id,
                'salon_id' => $complaint->salon_id,
            ],
            'related_salon_id' => $complaint->salon_id,
            'is_read' => false,
        ]);
    }

    /** @return array<string, mixed> */
    private function present(Complaint $complaint): array
    {
        return [
            'id' => $complaint->id,
            'subject' => $complaint->subject,
            'description' => $complaint->description,
            'status' => $complaint->status,
            'action_taken' => $complaint->action_taken,
            'resolution_note' => $complaint->resolution_note,
            'salon_id' => $complaint->salon_id,
            'salon_name' => $complaint->salon->name ?? 'Salon',
            'salon_status' => $complaint->salon->status ?? null,
            'owner_name' => $complaint->salon->admin->name ?? null,
            'owner_phone' => $complaint->salon->admin->phone ?? null,
            // The full name here, unlike the public review list: SuperAdmin is
            // judging a dispute and needs to know who is on each side of it.
            'customer_name' => $complaint->customer->name ?? 'Customer',
            'customer_phone' => $complaint->customer->phone ?? null,
            'appointment_date' => $complaint->appointment->appointment_date ?? null,
            'resolved_by' => $complaint->resolver->name ?? null,
            'resolved_at' => $complaint->resolved_at,
            'created_at' => $complaint->created_at,
            'age_label' => $this->reviews->ageLabel($complaint->created_at),
        ];
    }
}
