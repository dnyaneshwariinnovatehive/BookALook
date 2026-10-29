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

    protected static function booted()
    {
        static::saving(function ($model) {
            if (empty($model->updated_by)) {
                $uid = auth()->id() ?? User::where('role', 'admin')->value('id') ?? User::value('id');
                if (! $uid) {
                    $systemUser = User::create([
                        'id' => (string) \Illuminate\Support\Str::uuid(),
                        'name' => 'System Admin',
                        'phone' => '9999999999',
                        'password_hash' => bcrypt('password'),
                        'role' => 'admin',
                        'is_active' => true,
                    ]);
                    $uid = $systemUser->id;
                }
                $model->updated_by = $uid;
            }
        });
    }

    /**
     * Platform defaults, used until SuperAdmin overrides a key in this table.
     */
    public const DEFAULTS = [
        'cancellation_cutoff_minutes' => 90,
        'reschedule_cutoff_minutes' => 90,
        'appointment_start_early_minutes' => 30,
        'appointment_reminder_lead_minutes' => 120,
        'qr_validity_minutes' => 60,
        'same_day_change_abuse_threshold' => 2,
        'subscription_expiry_warning_days' => 3,
        // What one reward coin is worth in rupees.
        'coin_value_inr' => 1.0,
        // Coins handed to a salon the moment SuperAdmin approves it, so its
        // very first plan is part-paid before it has served anybody. Granted
        // once per salon, at whatever this says on the day of approval — later
        // changes never reprice a bonus already given.
        'welcome_bonus_coins' => 2300,
        // Local hour (0-23) for the daily renewal reminder. Mid-morning: the
        // owner is at the salon and not yet in the day's rush.
        'subscription_reminder_hour' => 11,
        // Days after a month closes before an unsettled Commission Model salon
        // loses access. The month's payout lands on the 1st and someone has to
        // work through the queue; a salon should not be shut for that.
        'commission_settlement_grace_days' => 7,
        // What happens to a Commission Model salon that has not paid what it
        // owes. See CommissionDuesService: each step on or off, and how many
        // days after the due date it starts. Dues below the minimum are left.
        'commission_dues_min_amount' => 200,
        'commission_dues_reminder_enabled' => true,
        'commission_dues_reminder_before_days' => 3,
        'commission_dues_reminder_every_days' => 3,
        'commission_dues_banner_enabled' => true,
        'commission_dues_banner_days' => 0,
        'commission_dues_force_advance_enabled' => true,
        'commission_dues_force_advance_days' => 3,
        'commission_dues_deduct_enabled' => true,
        'commission_dues_deduct_days' => 3,
        'commission_dues_stop_bookings_enabled' => true,
        'commission_dues_stop_bookings_days' => 10,
        'commission_dues_full_lock_enabled' => true,
        'commission_dues_full_lock_days' => 20,

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

        // Global toggles for WhatsApp notifications. SuperAdmin can turn them off.
        'whatsapp_booking_confirmed_enabled' => true,
        'whatsapp_appointment_reminder_enabled' => true,
        'whatsapp_appointment_cancelled_enabled' => true,
        'whatsapp_salon_closure_enabled' => true,
        'whatsapp_salon_deactivated_enabled' => true,
        
        // Limit on how many combos a salon can create.
        'combos_limit_per_salon' => 10,

        // How many cancellations and no-shows a customer may have before
        // booking is restricted. See CustomerStandingService. 0 = no limit.
        'customer_cancellation_limit' => 0,
        'customer_cancellation_count_mode' => 'total',
        'customer_no_show_limit' => 0,
        'customer_no_show_count_mode' => 'total',
        // block | full_payment | warn
        'customer_limit_action' => 'block',
        // How far back "in total" looks, in days. 0 = all time.
        'customer_limit_window_days' => 90,
        // Days after the last offence a restriction lifts. 0 = only SuperAdmin.
        'customer_limit_release_days' => 30,
        // Where salons pay BookALook — for a plan, and for what a payout says
        // they owe. One QR and UPI ID, set by SuperAdmin; blank until set.
        'payment_qr_url' => '',
        'payment_upi_id' => '',
        'payment_payee_name' => '',

        // First-Time Customer Discount platform policy limits & defaults
        'first_time_discount_min_percentage' => 5,
        'first_time_discount_max_percentage' => 50,
        'first_time_discount_default_percentage_cap' => 500.0,
        'first_time_discount_min_flat_amount' => 1.0,
        'first_time_discount_max_flat_amount' => 1000.0,
        'first_time_discount_default_flat_cap' => 1000.0,
        'first_time_discount_platform_max_cap' => 5000.0,
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
