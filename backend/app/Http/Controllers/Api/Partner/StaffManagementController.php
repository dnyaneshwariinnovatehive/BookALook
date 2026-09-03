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
        $staff = ServiceProvider::with(['user', 'services'])->where('salon_id', $salonId)->get();
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
                'auto_approve_leave' => false,
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
