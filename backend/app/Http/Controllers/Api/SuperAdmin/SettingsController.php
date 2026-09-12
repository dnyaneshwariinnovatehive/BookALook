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
            'coin_value_inr' => 'sometimes|numeric|min:0',
            'subscription_reminder_hour' => 'sometimes|integer|min:0|max:23',
            'commission_settlement_grace_days' => 'sometimes|integer|min:0|max:60',
            // Where every printed salon QR code lands. Changing it silently
            // redirects every poster already on a wall, which is the point —
            // but it has to be a real address.
            'public_web_url' => 'sometimes|string|max:255|url',
            // Blank is meaningful: it means "not listed yet", and the landing
            // page hides the button rather than offering a dead link.
            'android_app_url' => 'sometimes|nullable|string|max:255',
            'ios_app_url' => 'sometimes|nullable|string|max:255',
            'android_apk_url' => 'sometimes|nullable|string|max:255',
        ]);

        $user = $request->user();

        $allowedSettings = [
            'subscription_expiry_warning_days' => 'Number of days before subscription expiry to show a warning banner',
            'cancellation_cutoff_minutes' => 'Number of minutes before an appointment when cancellation is blocked',
            'reschedule_cutoff_minutes' => 'Number of minutes before an appointment when rescheduling is blocked',
            'appointment_start_early_minutes' => 'Number of minutes before an appointment start time when a provider can start it',
            'subscription_reminder_hour' => 'Hour of the day (0-23) when renewal reminders are sent to salon owners',
            'commission_settlement_grace_days' => 'Days after a month closes before an unsettled Commission Model salon is locked out',
        ];

        // Not an integer like the rest — a coin can be worth paise.
        if ($request->has('coin_value_inr')) {
            PlatformPolicySetting::updateOrCreate(
                ['setting_key' => 'coin_value_inr'],
                [
                    'setting_value' => (string) $request->input('coin_value_inr'),
                    'data_type' => 'decimal',
                    'description' => 'What one reward coin is worth, in rupees',
                    'updated_by' => $user->id,
                ]
            );
        }

        $urlSettings = [
            'public_web_url' => 'Where a scanned salon QR code lands. Every printed poster follows this.',
            'android_app_url' => 'Play Store listing for the customer app. Blank hides the Android button.',
            'ios_app_url' => 'App Store listing for the customer app. Blank hides the iPhone button.',
            'android_apk_url' => 'Direct Android build, for handing the app out before the stores approve it.',
        ];

        foreach ($urlSettings as $key => $description) {
            if ($request->has($key)) {
                $value = trim((string) $request->input($key));

                // A store link that is not live yet is stored empty rather than
                // as a placeholder, so the landing page knows to hide it.
                PlatformPolicySetting::updateOrCreate(
                    ['setting_key' => $key],
                    [
                        'setting_value' => $key === 'public_web_url'
                            ? rtrim($value, '/')
                            : $value,
                        'data_type' => 'string',
                        'description' => $description,
                        'updated_by' => $user->id,
                    ]
                );
            }
        }

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
