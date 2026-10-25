<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Salon;
use App\Models\SalonWorkingHour;
use App\Models\ServiceProvider;
use App\Models\ProviderWorkingHour;
use App\Services\GeoService;
use App\Services\SalonLinkService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Validator;
use App\Models\SalonPayout;
use App\Models\Appointment;
use App\Models\SalaryPayout;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Support\Str;
use App\Services\Notifications\NotificationService;

class SalonSettingsController extends Controller
{
    public function updateProfile(Request $request, $salon_id)
    {
        $salon = Salon::where('id', $salon_id)
            ->where('admin_id', $request->user()->id)
            ->firstOrFail();

        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:150',
            'phone' => 'nullable|string|max:15',
            'description' => 'nullable|string',
            'address' => 'nullable|string',
            'pincode' => 'nullable|string|max:10',
            'gender_focus' => 'nullable|string|'.\App\Support\GenderFocus::rule(),
            'cover_image' => 'nullable|image|mimes:jpeg,png,jpg,webp|max:5120',
            'map_url' => 'nullable|string|url|max:500',
            'advance_required' => 'nullable|boolean',
            'advance_percentage_default' => 'nullable|numeric|min:0|max:100',
        ]);

        if ($validator->fails()) {
            if ($request->hasFile('cover_image')) {
                \Illuminate\Support\Facades\Log::error('Upload error: ' . $request->file('cover_image')->getError() . ' - ' . $request->file('cover_image')->getErrorMessage());
            }
            return response()->json(['errors' => $validator->errors()], 422);
        }

        // Becoming single-gender while still offering services for the other
        // gender would leave customers shown services nobody can book. The
        // owner retires those first; nothing is removed on their behalf.
        $newFocus = $request->input('gender_focus');
        if ($request->has('gender_focus') && in_array($newFocus, [\App\Support\GenderFocus::MEN, \App\Support\GenderFocus::WOMEN], true)) {
            $other = $newFocus === \App\Support\GenderFocus::MEN
                ? \App\Support\GenderFocus::WOMEN
                : \App\Support\GenderFocus::MEN;

            $conflicting = \App\Models\Service::with('template:id,name')
                ->where('salon_id', $salon->id)
                ->where('is_active', true)
                ->where('gender_focus', $other)
                ->get()
                ->map(fn ($s) => $s->template->name ?? 'Service')
                ->values()
                ->all();

            if ($conflicting !== []) {
                $message = "Your salon still offers {$other} services: ".implode(', ', $conflicting)
                    .". Remove them before switching to {$newFocus}.";

                return response()->json([
                    'message' => $message,
                    'errors' => ['gender_focus' => [$message]],
                    'conflicting_services' => $conflicting,
                ], 422);
            }
        }

        $salon->name = $request->name;
        
        if ($request->has('description')) {
            $salon->description = $request->description;
        }
        
        if ($request->has('address')) {
            $salon->address = $request->address;
        }
        
        if ($request->has('pincode')) {
            $salon->pincode = $request->pincode;
        }
        
        if ($request->has('gender_focus')) {
            $salon->gender_focus = $request->gender_focus;
        }

        if ($request->has('map_url')) {
            $salon->map_url = $request->map_url;
        }

        if ($request->has('advance_required')) {
            $salon->advance_required = $request->boolean('advance_required');
        }

        if ($request->has('advance_percentage_default')) {
            $salon->advance_percentage_default = $request->advance_percentage_default;
        }

        if ($request->hasFile('cover_image')) {
            $file = $request->file('cover_image');
            $extension = strtolower($file->getClientOriginalExtension());
            $filename = \Illuminate\Support\Str::uuid().'.'.$extension;
            $path = $file->storeAs('salons', $filename, 'public');
            $salon->cover_photo_url = asset('storage/'.$path);
        }

        $salon->save();

        // If phone is provided and admin user has no phone or wants to update, we update the admin user's phone,
        // since the salon doesn't have a phone field directly. It is attached to the admin.
        if ($request->has('phone') && $request->phone) {
            $admin = $request->user();
            $admin->phone = $request->phone;
            $admin->save();
        }

        return response()->json([
            'message' => 'Profile updated successfully',
            'salon' => $salon
        ]);
    }
    public function getWorkingHours(Request $request, $salon_id)
    {
        $salon = Salon::find($salon_id);
        if (! $salon) {
            return response()->json(['message' => 'Salon not found.'], 404);
        }

        $hours = SalonWorkingHour::where('salon_id', $salon_id)
            ->orderBy('day_of_week', 'asc')
            ->get();

        $keyed = $hours->keyBy('day_of_week');
        $fullWeek = [];
        $hasAny = $hours->isNotEmpty();

        for ($day = 0; $day < 7; $day++) {
            if ($keyed->has($day)) {
                $fullWeek[] = $keyed->get($day);
            } else {
                $fullWeek[] = [
                    'day_of_week' => $day,
                    'is_closed' => false,
                    'open_time' => '09:00:00',
                    'close_time' => '18:00:00',
                ];
            }
        }

        return response()->json([
            'working_hours' => $fullWeek,
            'is_default' => ! $hasAny,
        ]);
    }

    public function updateWorkingHours(Request $request, $salon_id)
    {
        $salon = Salon::find($salon_id);
        if (! $salon) {
            return response()->json(['message' => 'Salon not found.'], 404);
        }

        $user = $request->user();
        if ($user && $user->role !== 'superadmin' && $salon->admin_id !== $user->id) {
            return response()->json(['message' => 'You are not authorized to update timings for this salon.'], 403);
        }

        $validator = Validator::make($request->all(), [
            'working_hours' => 'required|array|size:7',
            'working_hours.*.day_of_week' => 'required|integer|min:0|max:6',
            'working_hours.*.is_closed' => 'required|boolean',
            'working_hours.*.open_time' => 'nullable|date_format:H:i:s,H:i|required_if:working_hours.*.is_closed,false',
            'working_hours.*.close_time' => 'nullable|date_format:H:i:s,H:i|required_if:working_hours.*.is_closed,false',
        ]);

        $validator->after(function ($validator) use ($request) {
            $hours = $request->input('working_hours');
            if (! is_array($hours)) {
                return;
            }

            foreach ($hours as $index => $hour) {
                if (! empty($hour['is_closed'])) {
                    continue;
                }
                $open = $hour['open_time'] ?? null;
                $close = $hour['close_time'] ?? null;
                if ($open && $close) {
                    $openSec = strtotime("1970-01-01 $open");
                    $closeSec = strtotime("1970-01-01 $close");
                    if ($openSec !== false && $closeSec !== false && $closeSec <= $openSec) {
                        $validator->errors()->add("working_hours.{$index}.close_time", 'Closing time must be after opening time.');
                    }
                }
            }
        });

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $hours = $request->working_hours;

        // Normalize time strings to ensure H:i:s format and clean nulls for closed days
        $normalizedHours = [];
        foreach ($hours as $hour) {
            $isClosed = (bool) $hour['is_closed'];
            $open = $isClosed ? null : ($hour['open_time'] ?? null);
            $close = $isClosed ? null : ($hour['close_time'] ?? null);

            if ($open && strlen($open) === 5) {
                $open .= ':00';
            }
            if ($close && strlen($close) === 5) {
                $close .= ':00';
            }

            $normalizedHours[] = [
                'day_of_week' => (int) $hour['day_of_week'],
                'is_closed' => $isClosed,
                'open_time' => $open,
                'close_time' => $close,
            ];
        }

        try {
            DB::transaction(function () use ($salon_id, $normalizedHours) {
                foreach ($normalizedHours as $hour) {
                    SalonWorkingHour::updateOrCreate(
                        [
                            'salon_id' => $salon_id,
                            'day_of_week' => $hour['day_of_week'],
                        ],
                        [
                            'is_closed' => $hour['is_closed'],
                            'open_time' => $hour['open_time'],
                            'close_time' => $hour['close_time'],
                        ]
                    );
                }

                // Automatically synchronize working hours for providers configured to follow salon timings.
                // Providers with customized schedules (use_salon_hours = false) are preserved untouched.
                $hasUseSalonHours = Schema::hasColumn('service_providers', 'use_salon_hours');
                $syncProvidersQuery = ServiceProvider::where('salon_id', $salon_id);
                if ($hasUseSalonHours) {
                    $syncProvidersQuery->where('use_salon_hours', true);
                }
                $syncProviders = $syncProvidersQuery->get();

                foreach ($syncProviders as $syncProvider) {
                    foreach ($normalizedHours as $hour) {
                        ProviderWorkingHour::updateOrCreate(
                            [
                                'provider_id' => $syncProvider->id,
                                'day_of_week' => $hour['day_of_week'],
                            ],
                            [
                                'is_weekly_off' => (bool) $hour['is_closed'],
                                'shift_start' => $hour['open_time'],
                                'shift_end' => $hour['close_time'],
                                'break_start' => null,
                                'break_end' => null,
                            ]
                        );
                    }
                }
            });
        } catch (\Throwable $e) {
            Log::error('Failed to update working hours: ' . $e->getMessage(), [
                'salon_id' => $salon_id,
                'trace' => $e->getTraceAsString(),
            ]);

            return response()->json([
                'message' => 'Failed to update working hours: ' . $e->getMessage(),
            ], 500);
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

    public function deactivate(Request $request, $salon_id, NotificationService $notifications)
    {
        $salon = Salon::where('id', $salon_id)
            ->where('admin_id', $request->user()->id)
            ->firstOrFail();

        if ($salon->status === 'deactivated') {
            return response()->json(['message' => 'Salon is already deactivated.'], 200);
        }

        // Check for pending payouts (platform <-> salon)
        $hasPendingSalonPayouts = SalonPayout::where('salon_id', $salon->id)
            ->where('status', '!=', 'distributed')
            ->exists();
            
        if ($hasPendingSalonPayouts) {
            return response()->json([
                'error_code' => 'HAS_PENDING_PAYOUTS',
                'message' => 'Cannot deactivate salon while platform payouts are pending settlement. Please clear your payouts first.'
            ], 422);
        }

        // Check for upcoming appointments
        $hasUpcomingAppointments = Appointment::where('salon_id', $salon->id)
            ->whereIn('status', ['pending', 'confirmed'])
            ->where('appointment_date', '>=', \Carbon\Carbon::today())
            ->exists();

        if ($hasUpcomingAppointments && !$request->boolean('force_close_schedule')) {
            return response()->json([
                'error_code' => 'HAS_UPCOMING_APPOINTMENTS',
                'message' => 'You have upcoming appointments scheduled. Please cancel or complete them before deactivating.'
            ], 422);
        }

        if ($hasUpcomingAppointments && $request->boolean('force_close_schedule')) {
            // Overwrite salon timings to closed on all days
            \App\Models\SalonWorkingHour::where('salon_id', $salon->id)->update([
                'is_closed' => true,
                'open_time' => null,
                'close_time' => null
            ]);
            return response()->json([
                'error_code' => 'SCHEDULE_CLOSED',
                'message' => 'Your salon timings have been closed for all days. No new bookings will be accepted. Please complete or cancel your upcoming appointments before trying to deactivate again.'
            ], 422);
        }

        // Generate Staff Dues PDF
        $pendingSalaries = SalaryPayout::with('provider.user')
            ->where('salon_id', $salon->id)
            ->where('status', 'pending')
            ->get();

        $pdf = Pdf::loadView('staff_dues', [
            'salon' => $salon,
            'salaries' => $pendingSalaries
        ])->setOptions(['isRemoteEnabled' => true])->output();

        $path = 'salons/staff_dues_' . $salon->id . '_' . Str::random(6) . '.pdf';
        \Illuminate\Support\Facades\Storage::disk('public')->put($path, $pdf);
        $pdfUrl = asset('storage/' . $path);

        // Deactivate the salon
        $salon->status = 'deactivated';
        $salon->save();

        // Trigger WhatsApp with the generated PDF
        $notifications->salonDeactivated($salon, $pdfUrl);

        return response()->json([
            'success' => true,
            'message' => 'Salon has been successfully deactivated.'
        ]);
    }
}
