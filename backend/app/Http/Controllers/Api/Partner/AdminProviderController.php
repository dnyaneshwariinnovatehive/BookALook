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

        // A person has one provider profile, at one salon. When it is tied to
        // another of the owner's salons, this salon says where instead of
        // offering the switch — and never shows that salon's profile as its own.
        $elsewhere = $this->workingElsewhere($provider, $salonId, $salon);
        if ($provider && $provider->salon_id !== $salonId) {
            $provider = null;
        }

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
                'use_salon_hours' => (bool) ($provider->use_salon_hours ?? true),
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
            'provider_elsewhere' => $elsewhere,
        ]);
    }

    /**
     * The other salon that holds the owner's provider profile, when it is
     * theirs to keep: they work there now, or have served customers there.
     *
     * An owner can be a service provider at one salon only. A profile that was
     * switched off without ever being booked is not holding anything, so it may
     * move; one with bookings stays, or that salon's history would point at a
     * provider who now belongs somewhere else.
     *
     * @return array{salon_id: string, salon_name: string, is_active: bool, message: string}|null
     */
    private function workingElsewhere(?ServiceProvider $provider, string $salonId, Salon $here): ?array
    {
        if (! $provider || $provider->salon_id === $salonId) {
            return null;
        }

        $active = ! $provider->trashed() && $provider->is_active;
        $served = Appointment::where('salon_id', $provider->salon_id)
            ->where(function ($q) use ($provider) {
                $q->where('appointed_provider_id', $provider->id)
                  ->orWhere('serving_provider_id', $provider->id);
            })
            ->exists();

        if (! $active && ! $served) {
            return null;
        }

        $name = Salon::whereKey($provider->salon_id)->value('name') ?? 'another salon';

        return [
            'salon_id' => $provider->salon_id,
            'salon_name' => $name,
            'is_active' => $active,
            'message' => $active
                ? "You already work as a service provider at {$name}. An owner can be a service provider at only one salon, so this option is not available at {$here->name}."
                : "Your service provider profile belongs to {$name}, where you have served customers. An owner can be a service provider at only one salon, so this option is not available at {$here->name}.",
        ];
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
                ->lockForUpdate()
                ->first();

            if ($elsewhere = $this->workingElsewhere($provider, $salonId, $salon)) {
                DB::rollBack();

                return response()->json([
                    'error_code' => 'PROVIDER_AT_OTHER_SALON',
                    'message' => $elsewhere['message'],
                    'provider_elsewhere' => $elsewhere,
                ], 409);
            }

            if (! $enabled) {
                // Disable provider mode safely:
                // Do not delete rows, foreign keys, working hours or appointment history.
                // A profile parked at another salon is not this salon's to touch.
                if ($provider && $provider->salon_id === $salonId) {
                    $provider->is_active = false;
                    $provider->save();
                }

                DB::commit();

                return $this->status($request, $salonId);
            }

            // Enabling provider mode:
            $useSalonHours = $request->has('use_salon_hours') ? $request->boolean('use_salon_hours') : true;

            if ($provider) {
                if ($provider->trashed()) {
                    $provider->restore();
                }
                if ($provider->salon_id !== $salonId) {
                    // An unused profile moving over from another salon: that
                    // salon's services and hours mean nothing here.
                    $provider->services()->detach();
                    ProviderWorkingHour::where('provider_id', $provider->id)->delete();
                }
                $provider->salon_id = $salonId;
                $provider->is_active = true;
                $provider->auto_approve_leave = true;
                $provider->use_salon_hours = $useSalonHours;
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
                    'use_salon_hours' => $useSalonHours,
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
