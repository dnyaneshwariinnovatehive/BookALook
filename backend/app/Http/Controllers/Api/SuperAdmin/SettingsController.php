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
        // If empty, return a default
        if ($settings->isEmpty()) {
            return response()->json([
                'success' => true,
                'settings' => [
                    'subscription_expiry_warning_days' => 3
                ]
            ]);
        }

        $formatted = [];
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
            'subscription_expiry_warning_days' => 'required|integer|min:1|max:30',
        ]);

        $user = $request->user();

        PlatformPolicySetting::updateOrCreate(
            ['setting_key' => 'subscription_expiry_warning_days'],
            [
                'setting_value' => (string)$request->subscription_expiry_warning_days,
                'data_type' => 'integer',
                'description' => 'Number of days before subscription expiry to show a warning banner',
                'updated_by' => $user->id
            ]
        );

        return response()->json([
            'success' => true,
            'message' => 'Policy settings updated successfully'
        ]);
    }
}
