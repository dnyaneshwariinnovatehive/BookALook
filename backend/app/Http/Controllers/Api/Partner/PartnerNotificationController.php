<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\Notification;
use App\Support\NotificationInbox;
use Illuminate\Http\Request;

/**
 * The salon owner's inbox. Renewal reminders land here, which is why it stays
 * reachable while the plan is lapsed.
 */
class PartnerNotificationController extends Controller
{
    public function index(Request $request)
    {
        $query = NotificationInbox::visible(NotificationInbox::forUser($request->user()->id));
        NotificationInbox::inPeriod($query, NotificationInbox::period($request));

        $notifications = $query
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
                'is_read' => (bool) $n->is_read,
                'created_at' => $n->created_at,
            ])->values(),
            // Across the whole inbox, whatever filter is showing.
            'unread_count' => NotificationInbox::visible(NotificationInbox::forUser($request->user()->id))
                ->where('is_read', false)
                ->count(),
        ]);
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
        Notification::where('user_id', $request->user()->id)
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
        $deleted = NotificationInbox::dismiss(NotificationInbox::forUser($request->user()->id), $request);

        return response()->json(['message' => 'Notifications deleted.', 'deleted' => $deleted]);
    }
}
