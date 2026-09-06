<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\PlatformPolicySetting;
use Illuminate\Support\Facades\DB;

class SettingsController extends Controller
{
    public function getPolicySettings()
    {
        $settings = PlatformPolicySetting::all();
        
        $formatted = PlatformPolicySetting::DEFAULTS; // Start with defaults
        
        foreach ($settings as $setting) {
            $value = $setting->setting_value;
            if ($setting->data_type === 'integer') {
                $value = (int)$value;
            } elseif ($setting->data_type === 'boolean') {
                $value = filter_var($value, FILTER_VALIDATE_BOOLEAN);
            } elseif ($setting->data_type === 'decimal') {
                $value = (float)$value;
            }
            $formatted[$setting->setting_key] = $value;
        }

        return response()->json([
            'success' => true,
            'settings' => $formatted
        ]);
    }

    public function updatePolicySettings(Request $request)
    {
        $request->validate([
            'subscription_expiry_warning_days' => 'sometimes|integer|min:1|max:30',
            'cancellation_cutoff_minutes' => 'sometimes|integer|min:0',
            'reschedule_cutoff_minutes' => 'sometimes|integer|min:0',
            'appointment_start_early_minutes' => 'sometimes|integer|min:0',
        ]);

        $user = $request->user();

        $allowedSettings = [
            'subscription_expiry_warning_days' => 'Number of days before subscription expiry to show a warning banner',
            'cancellation_cutoff_minutes' => 'Number of minutes before an appointment when cancellation is blocked',
            'reschedule_cutoff_minutes' => 'Number of minutes before an appointment when rescheduling is blocked',
            'appointment_start_early_minutes' => 'Number of minutes before an appointment start time when a provider can start it',
        ];

        foreach ($allowedSettings as $key => $description) {
            if ($request->has($key)) {
                PlatformPolicySetting::updateOrCreate(
                    ['setting_key' => $key],
                    [
                        'setting_value' => (string)$request->input($key),
                        'data_type' => 'integer',
                        'description' => $description,
                        'updated_by' => $user->id
                    ]
                );
            }
        }

        return response()->json([
            'success' => true,
            'message' => 'Policy settings updated successfully'
        ]);
    }
}
