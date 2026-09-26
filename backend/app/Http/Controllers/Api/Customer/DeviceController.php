<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\UserDevice;
use App\Services\Notifications\DeviceService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Lets a phone introduce itself to the push pipeline.
 *
 * The app calls register on launch and whenever the OS hands back a fresh
 * token, then calls unregister on sign-out. Both are best-effort housekeeping
 * on the app's side: a failure here is logged and retried by the app on the
 * next launch, and never blocks a booking.
 *
 * A customer may only ever manage their own devices. The owner is taken from
 * the Sanctum token and never from the request body, so there is no field here
 * that could be tampered with to point a device at another account.
 */
class DeviceController extends Controller
{
    public function __construct(private DeviceService $devices)
    {
    }

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

        $device = $this->devices->register($request->user(), $data);

        return response()->json([
            'message' => 'Device registered for push notifications.',
            'device' => $this->present($device),
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
        $released = $this->devices->unregister($request->user(), $data['push_token']);

        return response()->json([
            'message' => $released
                ? 'Device unregistered from push notifications.'
                : 'That device was not registered for push notifications.',
        ]);
    }

    /**
     * A cheap "I am still here" the app can call on open. Keeps
     * `last_active_at` meaningful without re-sending the whole token.
     */
    public function activity(Request $request): JsonResponse
    {
        $data = $request->validate([
            'push_token' => ['nullable', 'string', 'max:255'],
        ]);

        $this->devices->touch($request->user(), $data['push_token'] ?? null);

        return response()->json(['message' => 'Device activity recorded.']);
    }

    /**
     * What this account has registered, so a user can spot a phone they do not
     * recognise and remove it.
     */
    public function index(Request $request): JsonResponse
    {
        $devices = $this->devices->listFor($request->user(), UserDevice::APP_TYPE_CUSTOMER);

        return response()->json([
            'devices' => $devices->map(fn (UserDevice $device) => $this->present($device))->values(),
        ]);
    }

    /**
     * @return array<string, mixed>
     */
    private function present(UserDevice $device): array
    {
        return [
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
        ];
    }
}
