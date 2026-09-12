<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PlatformPolicySetting extends Model
{
    public $timestamps = false;
    protected $primaryKey = 'setting_key';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'setting_key',
        'setting_value',
        'data_type',
        'description',
        'updated_by',
    ];

    /**
     * Platform defaults, used until SuperAdmin overrides a key in this table.
     */
    public const DEFAULTS = [
        'cancellation_cutoff_minutes' => 90,
        'reschedule_cutoff_minutes' => 90,
        'appointment_start_early_minutes' => 30,
        'qr_validity_minutes' => 60,
        'same_day_change_abuse_threshold' => 2,
        'subscription_expiry_warning_days' => 3,
        // What one reward coin is worth in rupees.
        'coin_value_inr' => 1.0,
        // Local hour (0-23) for the daily renewal reminder. Mid-morning: the
        // owner is at the salon and not yet in the day's rush.
        'subscription_reminder_hour' => 11,
        // Days after a month closes before an unsettled Commission Model salon
        // loses access. The month's payout lands on the 1st and someone has to
        // work through the queue; a salon should not be shut for that.
        'commission_settlement_grace_days' => 7,

        // Where a scanned salon QR code lands. Held as a setting rather than an
        // env var because the address changes when the platform moves host, and
        // every printed QR in every salon keeps pointing at whatever this says.
        'public_web_url' => 'http://localhost:3000',

        // Where that landing page sends someone who does not have the app.
        // Empty until the listings are live; the page hides what it has no
        // link for rather than sending anyone to a dead store page.
        'android_app_url' => '',
        'ios_app_url' => '',
        // A direct build, for handing the app out before the stores approve it.
        'android_apk_url' => '',
    ];

    /** Settings that hold a URL rather than a number. */
    public const URL_KEYS = [
        'public_web_url',
        'android_app_url',
        'ios_app_url',
        'android_apk_url',
    ];

    /**
     * Read a policy value, cast to its declared data_type, falling back to the
     * platform default when SuperAdmin has not set it.
     */
    public static function value(string $key, mixed $default = null): mixed
    {
        $setting = static::find($key);

        if (! $setting) {
            return $default ?? (self::DEFAULTS[$key] ?? null);
        }

        return match ($setting->data_type) {
            'integer' => (int) $setting->setting_value,
            'decimal' => (float) $setting->setting_value,
            'boolean' => filter_var($setting->setting_value, FILTER_VALIDATE_BOOLEAN),
            default => $setting->setting_value,
        };
    }
}
