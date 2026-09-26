<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\NotificationPreference;
use App\Models\UserDevice;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * The Partner App's notification settings.
 *
 * Same five switches and same semantics as the customer endpoint, in a separate
 * controller for the same reason the device controller is: a partner's settings
 * live in a different app, ship on a different schedule, and are read through
 * `/api/partner/*`. The default app type differs, which is the whole reason
 * these rows are keyed by app in the first place.
 */
class NotificationPreferenceController extends Controller
{
    private const FIELDS = [
        'push_enabled',
        'booking_notifications',
        'appointment_reminders',
        'payment_notifications',
        'promotional_notifications',
    ];

    public function show(Request $request): JsonResponse
    {
        $data = $request->validate([
            'app_type' => ['sometimes', Rule::in([UserDevice::APP_TYPE_CUSTOMER, UserDevice::APP_TYPE_PARTNER])],
        ]);

        $preference = NotificationPreference::forUser(
            $request->user()->id,
            $data['app_type'] ?? UserDevice::APP_TYPE_PARTNER,
        );

        return response()->json([
            'preferences' => $preference->toApiArray(),
        ]);
    }

    public function update(Request $request): JsonResponse
    {
        $data = $request->validate([
            'app_type' => ['sometimes', Rule::in([UserDevice::APP_TYPE_CUSTOMER, UserDevice::APP_TYPE_PARTNER])],
            'push_enabled' => ['sometimes', 'boolean'],
            'booking_notifications' => ['sometimes', 'boolean'],
            'appointment_reminders' => ['sometimes', 'boolean'],
            'payment_notifications' => ['sometimes', 'boolean'],
            'promotional_notifications' => ['sometimes', 'boolean'],
        ]);

        $appType = $data['app_type'] ?? UserDevice::APP_TYPE_PARTNER;

        $switches = array_intersect_key($data, array_flip(self::FIELDS));

        if ($switches === []) {
            return response()->json([
                'preferences' => NotificationPreference::forUser($request->user()->id, $appType)->toApiArray(),
            ]);
        }

        $preference = NotificationPreference::updateOrCreate(
            ['user_id' => $request->user()->id, 'app_type' => $appType],
            $switches,
        );

        return response()->json([
            'message' => 'Notification preferences saved.',
            'preferences' => $preference->fresh()->toApiArray(),
        ]);
    }
}
