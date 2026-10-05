<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Salon;
use App\Models\WhatsAppMessage; // assuming this exists or campaign_recipients
use Carbon\Carbon;

class AutomatedMessagingController extends Controller
{
    public function getSettings(Request $request, $salon_id)
    {
        $salon = Salon::findOrFail($salon_id);

        // Verify the user is an admin or has access to this salon
        if ($salon->admin_id !== $request->user()->id) {
            return response()->json(['success' => false, 'message' => 'Unauthorized'], 403);
        }

        // We want to get analytics for "this month"
        $startOfMonth = Carbon::now()->startOfMonth();
        
        // Wait, where do we track sent messages? We have `whatsapp_messages` or `campaigns` tables.
        // The migration showed: `whatsapp_messages` with `campaign_id` and `category`.
        // Let's assume automated messages for 25 days and birthday are logged in `whatsapp_messages` with specific category or type.
        
        // Return dummy analytics for now if no messages are sent yet, but wire it up with the real tables.
        $thisMonthCount = \Illuminate\Support\Facades\DB::table('whatsapp_messages')
            ->where('related_salon_id', $salon->id)
            ->whereIn('template', ['25_days_reminder', 'birthday_message'])
            ->where('created_at', '>=', $startOfMonth)
            ->count();

        $totalSent = \Illuminate\Support\Facades\DB::table('whatsapp_messages')
            ->where('related_salon_id', $salon->id)
            ->whereIn('template', ['25_days_reminder', 'birthday_message'])
            ->count();
            
        $recentMessages = \Illuminate\Support\Facades\DB::table('whatsapp_messages')
            ->where('related_salon_id', $salon->id)
            ->whereIn('template', ['25_days_reminder', 'birthday_message'])
            ->orderBy('created_at', 'desc')
            ->take(5)
            ->get();

        return response()->json([
            'success' => true,
            'settings' => [
                'whatsapp_25_days_enabled' => (bool) $salon->whatsapp_25_days_enabled,
                'whatsapp_birthday_enabled' => (bool) $salon->whatsapp_birthday_enabled,
            ],
            'analytics' => [
                'this_month_sent' => $thisMonthCount,
                'total_sent' => $totalSent,
                'recent_messages' => $recentMessages,
            ]
        ]);
    }

    public function updateSettings(Request $request, $salon_id)
    {
        $salon = Salon::findOrFail($salon_id);

        if ($salon->admin_id !== $request->user()->id) {
            return response()->json(['success' => false, 'message' => 'Unauthorized'], 403);
        }

        $request->validate([
            'whatsapp_25_days_enabled' => 'sometimes|boolean',
            'whatsapp_birthday_enabled' => 'sometimes|boolean',
        ]);

        if ($request->has('whatsapp_25_days_enabled')) {
            $salon->whatsapp_25_days_enabled = $request->boolean('whatsapp_25_days_enabled');
        }

        if ($request->has('whatsapp_birthday_enabled')) {
            $salon->whatsapp_birthday_enabled = $request->boolean('whatsapp_birthday_enabled');
        }

        $salon->save();

        return response()->json([
            'success' => true,
            'message' => 'Automated messaging settings updated successfully.',
            'settings' => [
                'whatsapp_25_days_enabled' => (bool) $salon->whatsapp_25_days_enabled,
                'whatsapp_birthday_enabled' => (bool) $salon->whatsapp_birthday_enabled,
            ]
        ]);
    }
}
