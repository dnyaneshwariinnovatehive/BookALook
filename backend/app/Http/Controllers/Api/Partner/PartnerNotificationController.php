<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\Notification;
use App\Models\Salon;
use App\Support\NotificationInbox;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

/**
 * The salon owner's inbox. Renewal reminders land here, which is why it stays
 * reachable while the plan is lapsed.
 */
class PartnerNotificationController extends Controller
{
    public function index(Request $request)
    {
        $query = NotificationInbox::visible($this->inbox($request, $request->query('salon_id')));
        NotificationInbox::inPeriod($query, NotificationInbox::period($request));

        $notifications = $query
            ->with('salon:id,name')
            ->orderByDesc('created_at')
            ->limit((int) $request->get('limit', 50))
            ->get();

        return response()->json([
            'notifications' => $notifications->map(fn (Notification $n) => [
                'id' => $n->id,
                'type' => $n->type,
                'title' => $n->title,
                'message' => $n->message,
                'data' => $n->data,
                'salon_id' => $n->related_salon_id,
                // An owner with several branches reads one inbox; each notice
                // says which salon it is about.
                'salon_name' => $n->salon?->name,
                'is_read' => (bool) $n->is_read,
                'created_at' => $n->created_at,
            ])->values(),
            // Across the whole inbox, whatever filter is showing.
            'unread_count' => NotificationInbox::visible(NotificationInbox::forUser($request->user()->id))
                ->where('is_read', false)
                ->count(),
            'salons' => $this->salonFilters($request),
        ]);
    }

    /**
     * For an owner with more than one salon: each salon and its unread count,
     * for the filter at the top of the inbox. Empty for everyone else — one
     * salon needs no filter.
     *
     * @return array<int, array{id: string, name: string, unread_count: int}>
     */
    private function salonFilters(Request $request): array
    {
        $user = $request->user();

        if ($user->role !== 'admin') {
            return [];
        }

        $salons = Salon::where('admin_id', $user->id)->orderBy('name')->get(['id', 'name']);

        if ($salons->count() < 2) {
            return [];
        }

        $unread = NotificationInbox::visible(NotificationInbox::forUser($user->id))
            ->where('is_read', false)
            ->whereIn('related_salon_id', $salons->pluck('id'))
            ->selectRaw('related_salon_id, count(*) as aggregate')
            ->groupBy('related_salon_id')
            ->pluck('aggregate', 'related_salon_id');

        return $salons->map(fn (Salon $salon) => [
            'id' => $salon->id,
            'name' => $salon->name,
            'unread_count' => (int) ($unread[$salon->id] ?? 0),
        ])->values()->all();
    }

    /** The signed-in person's inbox, narrowed to one salon when asked. */
    private function inbox(Request $request, mixed $salonId): Builder
    {
        return NotificationInbox::forUser($request->user()->id)
            ->when(is_string($salonId) && $salonId !== '', fn ($q) => $q->where('related_salon_id', $salonId));
    }

    public function markRead(Request $request, $id)
    {
        $notification = Notification::where('user_id', $request->user()->id)->findOrFail($id);

        if (! $notification->is_read) {
            $notification->forceFill(['is_read' => true, 'read_at' => now()])->save();
        }

        return response()->json(['message' => 'Marked as read.']);
    }

    public function markAllRead(Request $request)
    {
        $this->inbox($request, $request->input('salon_id'))
            ->where('is_read', false)
            ->update(['is_read' => true, 'read_at' => now()]);

        return response()->json(['message' => 'All marked as read.']);
    }

    /** Delete one of the signed-in person's own notifications. */
    public function destroy(Request $request, $id)
    {
        $deleted = NotificationInbox::dismissOne(NotificationInbox::forUser($request->user()->id), (string) $id);

        if (! $deleted) {
            return response()->json(['message' => 'Notification not found.'], 404);
        }

        return response()->json(['message' => 'Notification deleted.']);
    }

    /** Delete several: given ids, everything in a period, or everything (`all`). */
    public function destroyMany(Request $request)
    {
        $deleted = NotificationInbox::dismiss($this->inbox($request, $request->input('salon_id')), $request);

        return response()->json(['message' => 'Notifications deleted.', 'deleted' => $deleted]);
    }
}
