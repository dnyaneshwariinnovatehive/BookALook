<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Services\AuditLogger;
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
            // Zero is allowed and means "stop giving new salons a bonus".
            // Salons already granted one keep it either way.
            'welcome_bonus_coins' => 'sometimes|integer|min:0|max:1000000',
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

            // WhatsApp marketing. These bound the platform's own conduct rather
            // than any one plan — what counts as a lapsed customer, and the
            // hours during which nobody may be messaged at all.
            'marketing_inactive_customer_days' => 'sometimes|integer|min:7|max:730',
            'marketing_repeat_customer_visits' => 'sometimes|integer|min:2|max:50',
            'marketing_high_value_min_spend' => 'sometimes|numeric|min:0',
            'marketing_quiet_hours_start' => 'sometimes|integer|min:0|max:23',
            'marketing_quiet_hours_end' => 'sometimes|integer|min:0|max:23',
            // Zero removes the daily ceiling, leaving only the plan's monthly
            // allowance in the way.
            'marketing_daily_cap_per_salon' => 'sometimes|integer|min:0|max:100000',
            'marketing_require_explicit_opt_in' => 'sometimes|boolean',
        ]);

        $user = $request->user();

        // Snapshotted before anything moves, so the entry can show what each
        // rule used to be — the whole point of auditing a settings change.
        $keysBeing = array_keys($request->except(['_token', '_method']));
        $before = collect($keysBeing)
            ->mapWithKeys(fn ($key) => [$key => PlatformPolicySetting::value($key)])
            ->all();

        $allowedSettings = [
            'subscription_expiry_warning_days' => 'Number of days before subscription expiry to show a warning banner',
            'cancellation_cutoff_minutes' => 'Number of minutes before an appointment when cancellation is blocked',
            'reschedule_cutoff_minutes' => 'Number of minutes before an appointment when rescheduling is blocked',
            'appointment_start_early_minutes' => 'Number of minutes before an appointment start time when a provider can start it',
            'subscription_reminder_hour' => 'Hour of the day (0-23) when renewal reminders are sent to salon owners',
            'welcome_bonus_coins' => 'Free coins given to a salon when SuperAdmin approves it',
            'commission_settlement_grace_days' => 'Days after a month closes before an unsettled Commission Model salon is locked out',
            'marketing_inactive_customer_days' => 'Days without a visit before a customer counts as inactive and can be sent a win-back campaign',
            'marketing_repeat_customer_visits' => 'Completed visits before a customer is treated as a regular',
            'marketing_quiet_hours_start' => 'Hour of day (0-23) after which marketing messages are held until morning',
            'marketing_quiet_hours_end' => 'Hour of day (0-23) before which marketing messages are held',
            'marketing_daily_cap_per_salon' => 'Most marketing messages one salon may send in a day, whatever its plan allows for the month. 0 removes the cap',
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

        // Rupees, so the same decimal treatment as a coin's value.
        if ($request->has('marketing_high_value_min_spend')) {
            PlatformPolicySetting::updateOrCreate(
                ['setting_key' => 'marketing_high_value_min_spend'],
                [
                    'setting_value' => (string) $request->input('marketing_high_value_min_spend'),
                    'data_type' => 'decimal',
                    'description' => 'Lifetime spend, in rupees, at or above which a customer is treated as high value',
                    'updated_by' => $user->id,
                ]
            );
        }

        // The switch that decides whether marketing reaches anyone at all: on,
        // only customers who have opted in are messaged; off, a completed
        // booking is treated as permission. An opt-out wins either way.
        if ($request->has('marketing_require_explicit_opt_in')) {
            PlatformPolicySetting::updateOrCreate(
                ['setting_key' => 'marketing_require_explicit_opt_in'],
                [
                    'setting_value' => $request->boolean('marketing_require_explicit_opt_in') ? '1' : '0',
                    'data_type' => 'boolean',
                    'description' => 'Require customers to opt in before any salon may send them marketing',
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

        $after = collect($keysBeing)
            ->mapWithKeys(fn ($key) => [$key => PlatformPolicySetting::value($key)])
            ->all();

        // Only worth an entry if something actually moved — saving the form
        // unchanged is not a platform policy change.
        if ($before != $after) {
            AuditLogger::record(
                action: AuditLog::POLICY_UPDATED,
                label: 'Platform policy',
                before: $before,
                after: $after,
            );
        }

        return response()->json([
            'success' => true,
            'message' => 'Policy settings updated successfully'
        ]);
    }
}
