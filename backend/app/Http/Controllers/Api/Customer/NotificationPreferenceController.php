<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\NotificationPreference;
use App\Models\UserDevice;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * The settings screen's view of "what may we tell you, and how".
 *
 * The Customer App already had a Push Notifications switch. It was stored in
 * SharedPreferences and read by nothing, so it was a switch that controlled
 * nothing. This endpoint is what makes it real: the toggle now travels to the
 * server, where the push job consults it before addressing a handset.
 *
 * Only the caller's own row is ever touched, and the user comes from the token.
 */
class NotificationPreferenceController extends Controller
{
    /**
     * The switches a client may set, and their defaults. Validated against this
     * list rather than hand-written per field so the model, the validation and
     * the response can never disagree about what exists.
     */
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
            $data['app_type'] ?? UserDevice::APP_TYPE_CUSTOMER,
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

        $appType = $data['app_type'] ?? UserDevice::APP_TYPE_CUSTOMER;

        // Only the keys the client actually sent. A partial update must not
        // reset the switches the client did not mention.
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
