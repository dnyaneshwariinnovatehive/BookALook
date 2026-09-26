<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\UserDevice;
use App\Services\Notifications\DeviceService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * The Partner App's end of the same conversation the Customer App has with
 * DeviceController.
 *
 * Deliberately a near-copy rather than a shared base class: the two apps will
 * drift, the validation rules will differ the day iOS arrives for one and not
 * the other, and a controller with a protected method and a constructor
 * parameter purely to avoid twelve duplicated lines is a worse trade than the
 * duplication. The behaviour that actually matters — who owns a token — lives
 * once, in DeviceService.
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

        $released = $this->devices->unregister($request->user(), $data['push_token']);

        return response()->json([
            'message' => $released
                ? 'Device unregistered from push notifications.'
                : 'That device was not registered for push notifications.',
        ]);
    }

    public function activity(Request $request): JsonResponse
    {
        $data = $request->validate([
            'push_token' => ['nullable', 'string', 'max:255'],
        ]);

        $this->devices->touch($request->user(), $data['push_token'] ?? null);

        return response()->json(['message' => 'Device activity recorded.']);
    }

    public function index(Request $request): JsonResponse
    {
        $devices = $this->devices->listFor($request->user(), UserDevice::APP_TYPE_PARTNER);

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
            'push_token' => $device->maskedToken(),
            'is_active' => (bool) $device->is_active,
            'last_active_at' => $device->last_active_at,
        ];
    }
}
