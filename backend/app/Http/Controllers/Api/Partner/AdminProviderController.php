<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use App\Models\ProviderWorkingHour;
use App\Models\Salon;
use App\Models\SalonWorkingHour;
use App\Models\Service;
use App\Models\ServiceProvider;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

class AdminProviderController extends Controller
{
    /**
     * Get the current Admin service-provider mode status, configuration,
     * validation checks, and any upcoming appointments.
     */
    public function status(Request $request, string $salonId)
    {
        $salon = Salon::find($salonId);
        if (! $salon) {
            return response()->json(['message' => 'Salon not found.'], 404);
        }

        $user = $request->user();
        if ($user->role !== 'superadmin' && ($user->role !== 'admin' || $salon->admin_id !== $user->id)) {
            return response()->json(['message' => 'Only the salon owner can configure provider mode.'], 403);
        }

        $targetUser = ($user->role === 'admin') ? $user : User::find($salon->admin_id);
        if (! $targetUser) {
            return response()->json(['message' => 'Salon owner account not found.'], 404);
        }

        $provider = ServiceProvider::withTrashed()
            ->with(['services.template:id,name', 'workingHours'])
            ->where('user_id', $targetUser->id)
            ->first();

        // Validation checks
        $hasSalonHours = SalonWorkingHour::where('salon_id', $salonId)
            ->where('is_closed', false)
            ->whereNotNull('open_time')
            ->whereNotNull('close_time')
            ->exists()
            && SalonWorkingHour::where('salon_id', $salonId)->count() === 7;

        $isEnabled = (bool) ($provider && ! $provider->trashed() && $provider->is_active);

        $hasProviderHours = false;
        $hasServices = false;
        $upcomingCount = 0;

        if ($provider) {
            $hasProviderHours = ProviderWorkingHour::where('provider_id', $provider->id)
                ->where('is_weekly_off', false)
                ->whereNotNull('shift_start')
                ->whereNotNull('shift_end')
                ->exists();

            $hasServices = $provider->services()->count() > 0;

            $upcomingCount = Appointment::where('salon_id', $salonId)
                ->where(function ($q) use ($provider) {
                    $q->where('appointed_provider_id', $provider->id)
                      ->orWhere('serving_provider_id', $provider->id);
                })
                ->whereDate('appointment_date', '>=', Carbon::today())
                ->whereIn('status', ['scheduled', 'in_progress'])
                ->count();
        }

        $isReady = $isEnabled && $hasSalonHours && $hasProviderHours && $hasServices;

        return response()->json([
            'is_provider_enabled' => $isEnabled,
            'provider' => $provider ? [
                'id' => $provider->id,
                'user_id' => $provider->user_id,
                'salon_id' => $provider->salon_id,
                'specialization' => $provider->specialization,
                'is_active' => (bool) $provider->is_active,
                'auto_approve_leave' => (bool) $provider->auto_approve_leave,
                'services_count' => $provider->services->count(),
                'services' => $provider->services->map(fn ($s) => [
                    'id' => $s->id,
                    'name' => $s->template->name ?? $s->name ?? 'Service',
                    'price' => (float) $s->price,
                ]),
                'working_hours' => $provider->workingHours->sortBy('day_of_week')->values(),
            ] : null,
            'setup_validation' => [
                'salon_hours_configured' => $hasSalonHours,
                'admin_hours_configured' => $hasProviderHours,
                'services_assigned' => $hasServices,
                'is_ready_for_booking' => $isReady,
            ],
            'upcoming_appointments_count' => $upcomingCount,
        ]);
    }

    /**
     * Enable or disable Admin service-provider mode, with atomic service
     * assignments and timetable updates.
     */
    public function toggle(Request $request, string $salonId)
    {
        $salon = Salon::find($salonId);
        if (! $salon) {
            return response()->json(['message' => 'Salon not found.'], 404);
        }

        $user = $request->user();
        if ($user->role !== 'superadmin' && ($user->role !== 'admin' || $salon->admin_id !== $user->id)) {
            return response()->json(['message' => 'Only the salon owner can configure provider mode.'], 403);
        }

        $targetUser = ($user->role === 'admin') ? $user : User::find($salon->admin_id);
        if (! $targetUser) {
            return response()->json(['message' => 'Salon owner account not found.'], 404);
        }

        $validator = Validator::make($request->all(), [
            'enabled' => 'required|boolean',
            'specialization' => 'nullable|string|max:150',
            'service_ids' => 'nullable|array',
            'service_ids.*' => 'exists:services,id',
            'use_salon_hours' => 'nullable|boolean',
            'working_hours' => 'nullable|array|size:7',
            'working_hours.*.day_of_week' => 'required_with:working_hours|integer|min:0|max:6',
            'working_hours.*.is_weekly_off' => 'required_with:working_hours|boolean',
            'working_hours.*.shift_start' => 'nullable|date_format:H:i:s|required_if:working_hours.*.is_weekly_off,false',
            'working_hours.*.shift_end' => 'nullable|date_format:H:i:s|required_if:working_hours.*.is_weekly_off,false',
            'working_hours.*.break_start' => 'nullable|date_format:H:i:s',
            'working_hours.*.break_end' => 'nullable|date_format:H:i:s',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $enabled = $request->boolean('enabled');

        try {
            DB::beginTransaction();

            $provider = ServiceProvider::withTrashed()
                ->where('user_id', $targetUser->id)
                ->first();

            if (! $enabled) {
                // Disable provider mode safely:
                // Do not delete rows, foreign keys, working hours or appointment history.
                if ($provider) {
                    $provider->is_active = false;
                    $provider->save();
                }

                DB::commit();

                return $this->status($request, $salonId);
            }

            // Enabling provider mode:
            if ($provider) {
                if ($provider->trashed()) {
                    $provider->restore();
                }
                $provider->salon_id = $salonId;
                $provider->is_active = true;
                $provider->auto_approve_leave = true;
                if ($request->filled('specialization')) {
                    $provider->specialization = $request->specialization;
                }
                $provider->save();
            } else {
                $provider = ServiceProvider::create([
                    'user_id' => $targetUser->id,
                    'salon_id' => $salonId,
                    'specialization' => $request->input('specialization', 'Owner & Specialist'),
                    'base_salary' => 0.00,
                    'commission_percentage' => 0.00,
                    'auto_approve_leave' => true,
                    'is_active' => true,
                    'joined_at' => now(),
                ]);
            }

            // Sync assigned services if provided
            if ($request->has('service_ids') && is_array($request->service_ids)) {
                $validServiceIds = Service::where('salon_id', $salonId)
                    ->whereIn('id', $request->service_ids)
                    ->pluck('id')
                    ->all();
                $provider->services()->sync($validServiceIds);
            }

            // Configure Working Hours
            if ($request->boolean('use_salon_hours')) {
                $salonHours = SalonWorkingHour::where('salon_id', $salonId)->get();
                if ($salonHours->count() === 7) {
                    ProviderWorkingHour::where('provider_id', $provider->id)->delete();
                    foreach ($salonHours as $sh) {
                        ProviderWorkingHour::create([
                            'provider_id' => $provider->id,
                            'day_of_week' => $sh->day_of_week,
                            'is_weekly_off' => (bool) $sh->is_closed,
                            'shift_start' => $sh->is_closed ? null : $sh->open_time,
                            'shift_end' => $sh->is_closed ? null : $sh->close_time,
                            'break_start' => null,
                            'break_end' => null,
                        ]);
                    }
                }
            } elseif ($request->has('working_hours') && is_array($request->working_hours)) {
                ProviderWorkingHour::where('provider_id', $provider->id)->delete();
                foreach ($request->working_hours as $hour) {
                    ProviderWorkingHour::create([
                        'provider_id' => $provider->id,
                        'day_of_week' => $hour['day_of_week'],
                        'is_weekly_off' => (bool) $hour['is_weekly_off'],
                        'shift_start' => $hour['is_weekly_off'] ? null : $hour['shift_start'],
                        'shift_end' => $hour['is_weekly_off'] ? null : $hour['shift_end'],
                        'break_start' => $hour['break_start'] ?? null,
                        'break_end' => $hour['break_end'] ?? null,
                    ]);
                }
            } elseif ($provider->workingHours()->count() === 0) {
                // If no hours exist yet, check if salon hours are configured and copy them as initial default
                $salonHours = SalonWorkingHour::where('salon_id', $salonId)->get();
                if ($salonHours->count() === 7) {
                    foreach ($salonHours as $sh) {
                        ProviderWorkingHour::create([
                            'provider_id' => $provider->id,
                            'day_of_week' => $sh->day_of_week,
                            'is_weekly_off' => (bool) $sh->is_closed,
                            'shift_start' => $sh->is_closed ? null : $sh->open_time,
                            'shift_end' => $sh->is_closed ? null : $sh->close_time,
                            'break_start' => null,
                            'break_end' => null,
                        ]);
                    }
                }
            }

            DB::commit();

            return $this->status($request, $salonId);
        } catch (\Exception $e) {
            DB::rollBack();

            return response()->json([
                'message' => 'Failed to update service provider mode.',
                'error' => $e->getMessage(),
            ], 500);
        }
    }
}
