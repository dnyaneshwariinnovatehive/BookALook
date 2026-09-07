<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\Notification;
use Illuminate\Http\Request;

/**
 * The customer's in-app inbox. This is the channel we control end to end —
 * WhatsApp mirrors it but is never the only place a customer is told something.
 */
class NotificationController extends Controller
{
    public function index(Request $request)
    {
        $notifications = Notification::where('user_id', $request->user()->id)
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
                'appointment_id' => $n->related_appointment_id,
                'salon_id' => $n->related_salon_id,
                'is_read' => (bool) $n->is_read,
                'created_at' => $n->created_at,
            ])->values(),
            'unread_count' => Notification::where('user_id', $request->user()->id)
                ->where('is_read', false)
                ->count(),
        ]);
    }

    public function markRead(Request $request, $id)
    {
        $notification = Notification::where('user_id', $request->user()->id)->findOrFail($id);

        if (! $notification->is_read) {
            $notification->is_read = true;
            $notification->read_at = now();
            $notification->save();
        }

        return response()->json(['message' => 'Notification marked as read.']);
    }

    public function markAllRead(Request $request)
    {
        Notification::where('user_id', $request->user()->id)
            ->where('is_read', false)
            ->update(['is_read' => true, 'read_at' => now()]);

        return response()->json(['message' => 'All notifications marked as read.']);
    }
}
