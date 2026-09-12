<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Salon;
use App\Models\SalonWorkingHour;
use App\Services\GeoService;
use App\Services\SalonLinkService;
use Illuminate\Support\Facades\Validator;

class SalonSettingsController extends Controller
{
    public function getWorkingHours($salon_id)
    {
        $hours = SalonWorkingHour::where('salon_id', $salon_id)
            ->orderBy('day_of_week', 'asc')
            ->get();

        if ($hours->isEmpty()) {
            // Provide default structure if nothing exists
            $defaultHours = [];
            for ($i = 0; $i < 7; $i++) {
                $defaultHours[] = [
                    'day_of_week' => $i,
                    'is_closed' => false,
                    'open_time' => '09:00:00',
                    'close_time' => '18:00:00',
                ];
            }
            return response()->json(['working_hours' => $defaultHours]);
        }

        return response()->json(['working_hours' => $hours]);
    }

    public function updateWorkingHours(Request $request, $salon_id)
    {
        $validator = Validator::make($request->all(), [
            'working_hours' => 'required|array|size:7',
            'working_hours.*.day_of_week' => 'required|integer|min:0|max:6',
            'working_hours.*.is_closed' => 'required|boolean',
            'working_hours.*.open_time' => 'nullable|date_format:H:i:s|required_if:working_hours.*.is_closed,false',
            'working_hours.*.close_time' => 'nullable|date_format:H:i:s|required_if:working_hours.*.is_closed,false',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $hours = $request->working_hours;
        
        foreach ($hours as $hour) {
            SalonWorkingHour::updateOrCreate(
                [
                    'salon_id' => $salon_id,
                    'day_of_week' => $hour['day_of_week'],
                ],
                [
                    'is_closed' => $hour['is_closed'],
                    'open_time' => $hour['is_closed'] ? null : $hour['open_time'],
                    'close_time' => $hour['is_closed'] ? null : $hour['close_time'],
                ]
            );
        }

        return response()->json(['message' => 'Working hours updated successfully']);
    }

    /**
     * Where the salon actually is.
     *
     * Customers are shown salons nearest to them first, so a salon without a
     * pin sorts last however good it is. This is how an owner fixes that —
     * standing in their own doorway, tapping once.
     *
     * Marked `owner` because it came from the person who runs the place, which
     * outranks the city-centre guess the platform makes on their behalf.
     */
    public function updateLocation(Request $request, $salon_id)
    {
        $request->validate([
            'latitude' => 'required|numeric|between:-90,90',
            'longitude' => 'required|numeric|between:-180,180',
        ]);

        $salon = Salon::where('id', $salon_id)
            ->where('admin_id', $request->user()->id)
            ->firstOrFail();

        if (! app(GeoService::class)->isValid($request->latitude, $request->longitude)) {
            return response()->json([
                'success' => false,
                'message' => 'That does not look like a real location.',
            ], 422);
        }

        $salon->forceFill([
            'latitude' => $request->latitude,
            'longitude' => $request->longitude,
            'location_source' => 'owner',
        ])->save();

        return response()->json([
            'success' => true,
            'message' => 'Location saved. Customers nearby will now see you first.',
            'latitude' => (float) $salon->latitude,
            'longitude' => (float) $salon->longitude,
            'location_source' => $salon->location_source,
        ]);
    }

    /** What the app needs to draw the pin, and whether it is the owner's own. */
    public function getLocation(Request $request, $salon_id)
    {
        $salon = Salon::where('id', $salon_id)
            ->where('admin_id', $request->user()->id)
            ->firstOrFail();

        return response()->json([
            'success' => true,
            'latitude' => $salon->latitude === null ? null : (float) $salon->latitude,
            'longitude' => $salon->longitude === null ? null : (float) $salon->longitude,
            'location_source' => $salon->location_source,
            'city' => $salon->city?->only(['id', 'name', 'state']),
        ]);
    }

    /**
     * The link this salon's printed QR code carries.
     *
     * The app draws the code itself so the owner gets a real PNG to print
     * without the server needing an image library. All the server owns is the
     * address — which is the part that must never differ between a poster
     * printed today and one printed next year.
     */
    public function qrCode(Request $request, $salon_id, SalonLinkService $links)
    {
        $salon = Salon::where('id', $salon_id)
            ->where('admin_id', $request->user()->id)
            ->firstOrFail();

        return response()->json([
            'success' => true,
            'url' => $links->publicUrl($salon),
            'salon_name' => $salon->name,
            'salon_slug' => $salon->slug,
            'city' => $salon->city?->name,
        ]);
    }
}
