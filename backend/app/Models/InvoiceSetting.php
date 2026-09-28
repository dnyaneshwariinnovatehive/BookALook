<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * How invoices look — the branding SuperAdmin edits on the invoice format page.
 *
 * Mirrors PlatformPolicySetting deliberately: same key/value rows, same
 * data_type cast, same "default until overridden" rule. Read it through
 * ::all() or ::value() and the two settings systems are interchangeable.
 */
class InvoiceSetting extends Model
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
     *
     * The toggles default to on for everything that makes an invoice an
     * invoice, and off for anything that would put a blank row on a customer's
     * copy. A section nobody has filled in should not print a heading over
     * nothing.
     */
    public const DEFAULTS = [
        // Who is issuing the invoice. Shown in the letterhead.
        'invoice_business_name' => 'BookALook',
        'invoice_business_address' => '',
        'invoice_business_email' => '',
        'invoice_business_phone' => '',
        // Tax identity, printed only when tax_id_label is also set — an empty
        // label beside a number is worse than neither.
        'invoice_tax_id' => '',
        'invoice_tax_id_label' => 'GSTIN',

        // Branding.
        'invoice_logo_url' => '',
        // Hex, used for rules, headings and the totals block.
        'invoice_accent_color' => '#B08D57',
        'invoice_footer_note' => 'Thank you for booking with us.',
        'invoice_terms' => '',

        // Numbering. The sequence itself is not a setting; it is allocated per
        // year and stored under invoice_number_seq_{YEAR}.
        'invoice_number_prefix' => 'BAL',
        'invoice_number_padding' => 5,

        // Which parts of the document to print at all.
        'invoice_show_logo' => true,
        'invoice_show_business_address' => true,
        'invoice_show_tax_id' => true,
        'invoice_show_provider' => true,
        'invoice_show_duration_column' => true,
        'invoice_show_terms' => true,
        'invoice_show_balance_due' => true,
    ];

    /** Keys stored as a whole number. */
    public const INTEGER_KEYS = [
        'invoice_number_padding',
    ];

    /** Keys that are on/off switches. */
    public const BOOLEAN_KEYS = [
        'invoice_show_logo',
        'invoice_show_business_address',
        'invoice_show_tax_id',
        'invoice_show_provider',
        'invoice_show_duration_column',
        'invoice_show_terms',
        'invoice_show_balance_due',
    ];

    /**
     * Every setting as the invoice renderer wants it — typed, with defaults
     * filled in. This is the array that gets frozen into invoices.template, so
     * adding a key here is how a new printable section is introduced.
     *
     * Named `typed` rather than `allTyped` because `all()` on a model is
     * Eloquent's, and a static that shadows it is a trap for whoever reads
     * this next.
     *
     * @return array<string, mixed>
     */
    public static function typed(): array
    {
        $out = self::DEFAULTS;

        foreach (self::all() as $setting) {
            $out[$setting->setting_key] = match ($setting->data_type) {
                'integer' => (int) $setting->setting_value,
                'decimal' => (float) $setting->setting_value,
                'boolean' => filter_var($setting->setting_value, FILTER_VALIDATE_BOOLEAN),
                default => (string) $setting->setting_value,
            };
        }

        return $out;
    }

    /**
     * Read one invoice setting, cast to its declared data_type, falling back to
     * the platform default when SuperAdmin has not set it.
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
