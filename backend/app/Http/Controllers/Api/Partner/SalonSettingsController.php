<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\SalonWorkingHour;
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
}
