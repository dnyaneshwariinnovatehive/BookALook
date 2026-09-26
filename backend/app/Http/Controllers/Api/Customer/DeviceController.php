<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\UserDevice;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * Lets a phone introduce itself to the push pipeline.
 *
 * The app calls register on launch and whenever the OS hands back a fresh
 * token, then calls unregister on sign-out. Both are best-effort housekeeping
 * on the app's side: a failure here is logged and retried by the app on the
 * next launch, and never blocks a booking.
 */
class DeviceController extends Controller
{
    public function register(Request $request): JsonResponse
    {
        $data = $request->validate([
            'app_type' => ['required', Rule::in([UserDevice::APP_TYPE_CUSTOMER, UserDevice::APP_TYPE_PARTNER])],
            'platform' => ['required', Rule::in([UserDevice::PLATFORM_ANDROID, UserDevice::PLATFORM_IOS])],
            // Required, not nullable: a device with no token has nothing to push
            // to, and storing an empty row only produces a silent no-op later.
            'push_token' => ['required', 'string', 'max:255'],
            'app_version' => ['required', 'string', 'max:20'],
            'device_model' => ['nullable', 'string', 'max:100'],
            'os_version' => ['nullable', 'string', 'max:20'],
        ]);

        $user = $request->user();

        $device = DB::transaction(function () use ($data, $user) {
            // A push token belongs to a handset, not to an account. The same
            // person signs out and somebody else signs in on a shared phone, or
            // a customer is created for a booking made on a number that already
            // had the app installed. If the previous owner keeps the row active
            // then their next notification lands on a screen showing somebody
            // else's name, so the token is handed over rather than duplicated.
            //
            // Deactivated, not deleted: the delivery ledger points at these
            // rows, and a phone that comes back should not take its delivery
            // history down with it.
            UserDevice::query()
                ->where('push_token', $data['push_token'])
                ->where('user_id', '!=', $user->id)
                ->lockForUpdate()
                ->get()
                ->each(fn (UserDevice $previous) => $previous->forceFill([
                    'is_active' => false,
                    'last_active_at' => now(),
                ])->save());

            // Keyed on the user as well as the token: the unique index on those
            // two columns is what stops one account registering the same
            // install twice and quietly pushing to itself.
            return UserDevice::updateOrCreate(
                ['user_id' => $user->id, 'push_token' => $data['push_token']],
                [
                    'app_type' => $data['app_type'],
                    'platform' => $data['platform'],
                    'app_version' => $data['app_version'],
                    'device_model' => $data['device_model'] ?? null,
                    'os_version' => $data['os_version'] ?? null,
                    'is_active' => true,
                    'last_active_at' => now(),
                ],
            );
        });

        return response()->json([
            'message' => 'Device registered for push notifications.',
            'device' => [
                'id' => $device->id,
                'app_type' => $device->app_type,
                'platform' => $device->platform,
                'app_version' => $device->app_version,
                'device_model' => $device->device_model,
                'os_version' => $device->os_version,
                // Masked on the way out too. The app already knows its own
                // token, so echoing it back achieves nothing and puts it in
                // another log on the way there.
                'push_token' => $device->maskedToken(),
                'is_active' => (bool) $device->is_active,
                'last_active_at' => $device->last_active_at,
            ],
        ], $device->wasRecentlyCreated ? 201 : 200);
    }

    public function unregister(Request $request): JsonResponse
    {
        $data = $request->validate([
            'push_token' => ['required', 'string', 'max:255'],
        ]);

        // Scoped to the signed-in user, so a token can only ever be released by
        // the account that holds it. Sign-out should not be able to quietly
        // disable a notification for whoever registered that phone next.
        $released = UserDevice::query()
            ->where('user_id', $request->user()->id)
            ->where('push_token', $data['push_token'])
            ->update(['is_active' => false]);

        return response()->json([
            'message' => $released
                ? 'Device unregistered from push notifications.'
                : 'That device was not registered for push notifications.',
        ]);
    }
}
