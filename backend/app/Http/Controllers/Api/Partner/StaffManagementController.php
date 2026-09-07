<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\User;
use App\Models\ServiceProvider;
use App\Models\ProviderWorkingHour;
use App\Models\ProviderLeave;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

class StaffManagementController extends Controller
{
    public function index($salonId)
    {
        // workingHours is loaded so the edit screen can show what is actually
        // stored instead of falling back to defaults.
        $staff = ServiceProvider::with(['user', 'services.template:id,name', 'workingHours'])
            ->where('salon_id', $salonId)
            ->get();

        return response()->json(['staff' => $staff]);
    }

    public function store(Request $request, $salonId)
    {
        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:255',
            'phone' => 'required|string|unique:users',
            'email' => 'nullable|email|unique:users',
            'specialization' => 'nullable|string|max:150',
            'base_salary' => 'numeric|min:0',
            'commission_percentage' => 'numeric|min:0|max:100',
            'auto_approve_leave' => 'boolean',
            'service_ids' => 'array',
            'service_ids.*' => 'exists:services,id',
            'working_hours' => 'required|array|size:7',
            'working_hours.*.day_of_week' => 'required|integer|min:0|max:6',
            'working_hours.*.is_weekly_off' => 'required|boolean',
            'working_hours.*.shift_start' => 'nullable|date_format:H:i:s|required_if:working_hours.*.is_weekly_off,false',
            'working_hours.*.shift_end' => 'nullable|date_format:H:i:s|required_if:working_hours.*.is_weekly_off,false',
            'working_hours.*.break_start' => 'nullable|date_format:H:i:s',
            'working_hours.*.break_end' => 'nullable|date_format:H:i:s',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        try {
            DB::beginTransaction();

            // 1. Create User
            $user = User::create([
                'name' => $request->name,
                'phone' => $request->phone,
                'email' => $request->email,
                'password_hash' => Hash::make('staff1234'), // Default password
                'role' => 'service_provider',
                'is_active' => true,
            ]);

            // 2. Create Service Provider profile
            $provider = ServiceProvider::create([
                'user_id' => $user->id,
                'salon_id' => $salonId,
                'specialization' => $request->specialization,
                'base_salary' => $request->base_salary ?? 0,
                'commission_percentage' => $request->commission_percentage ?? 0,
                'auto_approve_leave' => $request->boolean('auto_approve_leave'),
                'is_active' => true,
                'joined_at' => now(),
            ]);

            // 3. Attach services
            if ($request->has('service_ids') && is_array($request->service_ids)) {
                $provider->services()->attach($request->service_ids);
            }

            // 4. Insert working hours
            foreach ($request->working_hours as $hour) {
                ProviderWorkingHour::create([
                    'provider_id' => $provider->id,
                    'day_of_week' => $hour['day_of_week'],
                    'is_weekly_off' => $hour['is_weekly_off'],
                    'shift_start' => $hour['is_weekly_off'] ? null : $hour['shift_start'],
                    'shift_end' => $hour['is_weekly_off'] ? null : $hour['shift_end'],
                    'break_start' => $hour['break_start'] ?? null,
                    'break_end' => $hour['break_end'] ?? null,
                ]);
            }

            DB::commit();

            return response()->json(['message' => 'Staff added successfully', 'provider' => $provider->load('user')], 201);
        } catch (\Exception $e) {
            DB::rollBack();
            return response()->json(['message' => 'Failed to add staff', 'error' => $e->getMessage()], 500);
        }
    }

    public function update(Request $request, $salonId, $staffId)
    {
        $provider = ServiceProvider::where('salon_id', $salonId)->findOrFail($staffId);
        $user = $provider->user;

        $validator = Validator::make($request->all(), [
            'name' => 'sometimes|required|string|max:255',
            'phone' => 'sometimes|required|string|unique:users,phone,' . $user->id,
            'email' => 'nullable|email|unique:users,email,' . $user->id,
            'specialization' => 'nullable|string|max:150',
            'base_salary' => 'sometimes|numeric|min:0',
            'commission_percentage' => 'sometimes|numeric|min:0|max:100',
            'auto_approve_leave' => 'sometimes|boolean',
            'service_ids' => 'sometimes|array',
            'service_ids.*' => 'exists:services,id',
            'working_hours' => 'sometimes|required|array|size:7',
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

        try {
            DB::beginTransaction();

            if ($request->has('name')) $user->name = $request->name;
            if ($request->has('phone')) $user->phone = $request->phone;
            if ($request->has('email')) $user->email = $request->email;
            $user->save();

            if ($request->has('specialization')) $provider->specialization = $request->specialization;
            if ($request->has('base_salary')) $provider->base_salary = $request->base_salary;
            if ($request->has('commission_percentage')) $provider->commission_percentage = $request->commission_percentage;
            if ($request->has('auto_approve_leave')) $provider->auto_approve_leave = $request->boolean('auto_approve_leave');
            $provider->save();

            if ($request->has('service_ids')) {
                $provider->services()->sync($request->service_ids);
            }

            if ($request->has('working_hours')) {
                ProviderWorkingHour::where('provider_id', $provider->id)->delete();
                foreach ($request->working_hours as $hour) {
                    ProviderWorkingHour::create([
                        'provider_id' => $provider->id,
                        'day_of_week' => $hour['day_of_week'],
                        'is_weekly_off' => $hour['is_weekly_off'],
                        'shift_start' => $hour['is_weekly_off'] ? null : $hour['shift_start'],
                        'shift_end' => $hour['is_weekly_off'] ? null : $hour['shift_end'],
                        'break_start' => $hour['break_start'] ?? null,
                        'break_end' => $hour['break_end'] ?? null,
                    ]);
                }
            }

            DB::commit();

            return response()->json(['message' => 'Staff updated successfully', 'provider' => $provider->load('user')], 200);
        } catch (\Exception $e) {
            DB::rollBack();
            return response()->json(['message' => 'Failed to update staff', 'error' => $e->getMessage()], 500);
        }
    }

    public function destroy($salonId, $staffId)
    {
        try {
            DB::beginTransaction();
            $provider = ServiceProvider::where('salon_id', $salonId)->findOrFail($staffId);
            
            // Delete working hours
            ProviderWorkingHour::where('provider_id', $provider->id)->delete();
            
            // Detach services
            $provider->services()->detach();
            
            // Delete provider profile (hard delete)
            $provider->delete();
            
            // Note: Not deleting the User model here because they might have other roles (like customer)
            // or historical appointments tied to them. In a real system, you might anonymize or deactivate.
            
            DB::commit();
            return response()->json(['message' => 'Staff deleted successfully']);
        } catch (\Exception $e) {
            DB::rollBack();
            return response()->json(['message' => 'Failed to delete staff', 'error' => $e->getMessage()], 500);
        }
    }

    public function getLeaves($salonId)
    {
        // Get all providers for this salon
        $providerIds = ServiceProvider::where('salon_id', $salonId)->pluck('id');

        $leaves = ProviderLeave::with(['provider.user'])
            ->whereIn('provider_id', $providerIds)
            ->orderBy('leave_date', 'desc')
            ->get();

        return response()->json(['leaves' => $leaves]);
    }

    /**
     * A staff member asks for time off.
     *
     * Whether it needs the admin's say-so is set per person: some staff are
     * trusted to book their own leave, others are not. Auto-approved leave is
     * still recorded as approved by nobody in particular, so the audit trail is
     * honest about how it was granted.
     */
    public function requestLeave(Request $request, $salonId)
    {
        $provider = ServiceProvider::where('user_id', $request->user()->id)
            ->where('salon_id', $salonId)
            ->first();

        if (! $provider) {
            return response()->json(['message' => 'You are not a service provider at this salon.'], 403);
        }

        $validator = Validator::make($request->all(), [
            'leave_date' => 'required|date|after_or_equal:today',
            'leave_type' => 'required|in:paid,unpaid',
            'is_full_day' => 'boolean',
            'start_time' => 'nullable|date_format:H:i:s|required_if:is_full_day,false',
            'end_time' => 'nullable|date_format:H:i:s|required_if:is_full_day,false|after:start_time',
            'reason' => 'nullable|string|max:255',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $alreadyBooked = ProviderLeave::where('provider_id', $provider->id)
            ->whereDate('leave_date', $request->leave_date)
            ->whereIn('status', [ProviderLeave::STATUS_PENDING, ProviderLeave::STATUS_APPROVED])
            ->exists();

        if ($alreadyBooked) {
            return response()->json(['message' => 'You already have leave on that date.'], 422);
        }

        $isFullDay = $request->boolean('is_full_day', true);
        $autoApprove = (bool) $provider->auto_approve_leave;

        $leave = ProviderLeave::create([
            'provider_id' => $provider->id,
            'leave_date' => $request->leave_date,
            'leave_type' => $request->leave_type,
            'is_full_day' => $isFullDay,
            'start_time' => $isFullDay ? null : $request->start_time,
            'end_time' => $isFullDay ? null : $request->end_time,
            'reason' => $request->reason,
            'status' => $autoApprove ? ProviderLeave::STATUS_APPROVED : ProviderLeave::STATUS_PENDING,
            'reviewed_at' => $autoApprove ? now() : null,
        ]);

        return response()->json([
            'message' => $autoApprove
                ? 'Leave approved automatically.'
                : 'Leave requested. Waiting for the salon admin.',
            'auto_approved' => $autoApprove,
            'leave' => $leave,
        ], 201);
    }

    /**
     * A staff member's own leave record.
     */
    public function myLeaves(Request $request, $salonId)
    {
        $provider = ServiceProvider::where('user_id', $request->user()->id)
            ->where('salon_id', $salonId)
            ->first();

        if (! $provider) {
            return response()->json(['message' => 'You are not a service provider at this salon.'], 403);
        }

        $leaves = ProviderLeave::where('provider_id', $provider->id)
            ->orderByDesc('leave_date')
            ->limit(100)
            ->get();

        return response()->json([
            'auto_approve_leave' => (bool) $provider->auto_approve_leave,
            'leaves' => $leaves,
        ]);
    }

    public function updateLeaveStatus(Request $request, $salonId, $leaveId)
    {
        $validator = Validator::make($request->all(), [
            'status' => 'required|in:approved,rejected',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $leave = ProviderLeave::where('id', $leaveId)->first();
        
        if (!$leave) {
            return response()->json(['message' => 'Leave not found'], 404);
        }

        // Verify the leave belongs to a provider in this salon
        $provider = ServiceProvider::where('id', $leave->provider_id)->where('salon_id', $salonId)->first();
        if (!$provider) {
            return response()->json(['message' => 'Unauthorized access to leave record'], 403);
        }

        $leave->status = $request->status;
        $leave->reviewed_by = $request->user()->id; // Assumes auth uses sanctum
        $leave->reviewed_at = now();
        $leave->save();

        return response()->json(['message' => 'Leave status updated', 'leave' => $leave]);
    }
}
