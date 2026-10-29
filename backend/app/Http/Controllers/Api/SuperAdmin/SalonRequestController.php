<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\SalonSupportRequest;
use App\Services\Notifications\NotificationService;
use App\Support\Notifications\NotificationType;
use Illuminate\Http\Request;

/**
 * What salon owners have written to BookALook from the Partner App, and the
 * replies. A reply reaches the owner as a Partner App notification.
 */
class SalonRequestController extends Controller
{
    public function index(Request $request)
    {
        $request->validate([
            'status' => 'nullable|in:open,resolved,all',
            'topic' => 'nullable|string|max:40',
            'search' => 'nullable|string|max:80',
        ]);

        $status = $request->input('status', 'open');

        $query = SalonSupportRequest::with(['salon:id,name,city_id', 'salon.city:id,name', 'user:id,name,phone', 'payout'])
            ->when($status !== 'all', fn ($q) => $q->where('status', $status))
            ->when($request->filled('topic'), fn ($q) => $q->where('topic', $request->topic))
            ->when($request->filled('search'), function ($q) use ($request) {
                $term = '%' . trim($request->search) . '%';
                $q->where(fn ($w) => $w->where('message', 'like', $term)
                    ->orWhereHas('salon', fn ($s) => $s->where('name', 'like', $term)));
            })
            ->latest();

        $page = $query->paginate((int) $request->input('per_page', 25));

        return response()->json([
            'success' => true,
            'data' => collect($page->items())->map(fn (SalonSupportRequest $r) => $this->row($r))->values(),
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'total' => $page->total(),
            ],
            'counts' => [
                'open' => SalonSupportRequest::where('status', SalonSupportRequest::STATUS_OPEN)->count(),
                'resolved' => SalonSupportRequest::where('status', SalonSupportRequest::STATUS_RESOLVED)->count(),
            ],
            'topics' => collect(SalonSupportRequest::TOPICS)->map(fn ($label, $key) => ['key' => $key, 'label' => $label])->values(),
        ]);
    }

    /** Answer the owner; optionally close the request in the same step. */
    public function reply(Request $request, string $id, NotificationService $notifications)
    {
        $data = $request->validate([
            'reply' => 'required|string|min:2|max:2000',
            'resolve' => 'boolean',
        ]);

        $supportRequest = SalonSupportRequest::with('salon')->findOrFail($id);
        $resolve = (bool) ($data['resolve'] ?? true);

        $supportRequest->update([
            'reply' => trim($data['reply']),
            'replied_by' => $request->user()->id,
            'replied_at' => now(),
            'status' => $resolve ? SalonSupportRequest::STATUS_RESOLVED : SalonSupportRequest::STATUS_OPEN,
            'resolved_at' => $resolve ? now() : null,
        ]);

        $salonName = $supportRequest->salon?->name ?? 'your salon';
        $notifications->send(
            recipient: $supportRequest->user_id,
            type: NotificationType::GENERAL,
            title: 'BookALook replied',
            message: "About {$salonName}: " . mb_strimwidth($supportRequest->reply, 0, 180, '…'),
            data: [
                'action' => 'salon_support_request',
                'salon_id' => $supportRequest->salon_id,
                'request_id' => $supportRequest->id,
            ],
            salon: $supportRequest->salon,
            dedupeKey: "salon-request-reply:{$supportRequest->id}:" . $supportRequest->replied_at->timestamp,
        );

        return response()->json([
            'success' => true,
            'message' => 'Reply sent to the salon owner.',
            'request' => $this->row($supportRequest->fresh(['salon.city', 'user', 'payout'])),
        ]);
    }

    public function updateStatus(Request $request, string $id)
    {
        $data = $request->validate(['status' => 'required|in:open,resolved']);
        $supportRequest = SalonSupportRequest::findOrFail($id);

        $supportRequest->update([
            'status' => $data['status'],
            'resolved_at' => $data['status'] === SalonSupportRequest::STATUS_RESOLVED ? now() : null,
        ]);

        return response()->json([
            'success' => true,
            'request' => $this->row($supportRequest->fresh(['salon.city', 'user', 'payout'])),
        ]);
    }

    private function row(SalonSupportRequest $r): array
    {
        return $r->present() + [
            'salon' => $r->salon ? [
                'id' => $r->salon->id,
                'name' => $r->salon->name,
                'city' => $r->salon->city?->name,
            ] : null,
            'owner' => $r->user ? ['name' => $r->user->name, 'phone' => $r->user->phone] : null,
        ];
    }
}
