<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Services\AuditLogger;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use App\Models\PlatformPolicySetting;
use App\Models\Invoice;
use App\Models\InvoiceSetting;
use App\Models\SettlementInvoice;
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

    /**
     * Everything the invoice format page needs: current values, the schema of
     * each field, and whether an invoice has ever been issued.
     *
     * The schema travels with the values on purpose. The page then renders
     * itself from what the server says is editable, so adding a printable
     * section is a change to InvoiceSetting::DEFAULTS and this endpoint — not a
     * coordinated edit across a PHP model and a TypeScript form.
     */
    public function getInvoiceSettings()
    {
        return response()->json([
            'success' => true,
            'settings' => InvoiceSetting::typed(),
            'schema' => $this->invoiceSchema(),
            'issued_count' => Invoice::count(),
            'settlement_issued_count' => SettlementInvoice::count(),
        ]);
    }

    public function updateInvoiceSettings(Request $request)
    {
        $request->validate([
            'invoice_business_name' => 'sometimes|required|string|max:150',
            'invoice_business_address' => 'sometimes|nullable|string|max:1000',
            'invoice_business_email' => 'sometimes|nullable|string|max:150|email',
            'invoice_business_phone' => 'sometimes|nullable|string|max:30',

            // The label is editable so a platform outside India is not forced to
            // print "GSTIN" over a number that is not one.
            'invoice_tax_id' => 'sometimes|nullable|string|max:60',
            'invoice_tax_id_label' => 'sometimes|nullable|string|max:30',

            'invoice_logo_url' => 'sometimes|nullable|string|max:500',
            'invoice_accent_color' => 'sometimes|required|string|regex:/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/',
            'invoice_footer_note' => 'sometimes|nullable|string|max:300',
            'invoice_terms' => 'sometimes|nullable|string|max:2000',

            'invoice_number_prefix' => 'sometimes|required|string|max:10',
            'invoice_number_padding' => 'sometimes|required|integer|min:1|max:12',

            'invoice_show_logo' => 'sometimes|boolean',
            'invoice_show_business_address' => 'sometimes|boolean',
            'invoice_show_tax_id' => 'sometimes|boolean',
            'invoice_show_provider' => 'sometimes|boolean',
            'invoice_show_duration_column' => 'sometimes|boolean',
            'invoice_show_terms' => 'sometimes|boolean',
            'invoice_show_balance_due' => 'sometimes|boolean',

            // The settlement statement a salon owner is given. The issuer and
            // branding keys above are shared on purpose — both documents come
            // from this company and must not look like two.
            'settlement_invoice_number_prefix' => 'sometimes|required|string|max:10',
            'settlement_invoice_number_padding' => 'sometimes|required|integer|min:1|max:12',
            'settlement_invoice_document_title' => 'sometimes|required|string|max:60',
            'settlement_invoice_footer_note' => 'sometimes|nullable|string|max:300',
            'settlement_invoice_show_billed_revenue' => 'sometimes|boolean',
            'settlement_invoice_show_appointments_count' => 'sometimes|boolean',
        ]);

        $user = $request->user();
        $descriptions = $this->invoiceDescriptions();

        $keysBeing = array_keys($request->except(['_token', '_method']));
        $before = collect($keysBeing)
            ->mapWithKeys(fn ($key) => [$key => InvoiceSetting::value($key)])
            ->all();

        foreach ($keysBeing as $key) {
            $isSwitch = in_array($key, InvoiceSetting::BOOLEAN_KEYS, true);
            $isWholeNumber = in_array($key, InvoiceSetting::INTEGER_KEYS, true);

            // Blanks are stored as blanks rather than dropped, so clearing the
            // address actually clears it instead of silently falling back to
            // whatever the default was.
            $raw = $isSwitch
                ? ($request->boolean($key) ? '1' : '0')
                : (string) $request->input($key);

            InvoiceSetting::updateOrCreate(
                ['setting_key' => $key],
                [
                    'setting_value' => $raw,
                    'data_type' => $isSwitch ? 'boolean' : ($isWholeNumber ? 'integer' : 'string'),
                    'description' => $descriptions[$key] ?? null,
                    'updated_by' => $user->id,
                ]
            );
        }

        $after = collect($keysBeing)
            ->mapWithKeys(fn ($key) => [$key => InvoiceSetting::value($key)])
            ->all();

        // Saving the form untouched is not a change worth an audit entry — the
        // log is only useful if an entry means something moved.
        if ($before != $after) {
            AuditLogger::record(
                action: AuditLog::INVOICE_SETTINGS_UPDATED,
                // Both documents, not just the customer one. Half these keys
                // change settlement statements too, and an audit trail that
                // calls that "Invoice format" is what makes the blast radius
                // of a change hard to reconstruct later.
                label: 'Invoice & statement format',
                before: $before,
                after: $after,
            );
        }

        return response()->json([
            'success' => true,
            'message' => 'Invoice & statement format updated successfully',
            'settings' => InvoiceSetting::typed(),
        ]);
    }

    /**
     * How each invoice field behaves, for the format page to render from.
     *
     * Every field carries a `scope` saying which document it actually reaches:
     * `both`, `invoice` or `settlement`. This is not decoration — it is the
     * correction to a trap the page used to fall into. The show/hide switches
     * for the letterhead (`invoice_show_logo`, `invoice_show_business_address`,
     * `invoice_show_tax_id`) and the terms live in the same group as the
     * customer-only columns, so grouping alone implied they belonged to the
     * customer invoice when in fact switching the logo off also takes it off
     * every settlement statement. The scope is read from the two templates
     * rather than guessed from the key's name, so it cannot drift when a
     * template changes what it prints.
     *
     * @return array<string, array{label: string, kind: string, group: string, group_title: string, scope: string, hint?: string}>
     */
    private function invoiceSchema(): array
    {
        $both = 'both';
        $invoice = 'invoice';
        $settlement = 'settlement';

        $letterhead = 'Letterhead';
        $numbering = 'Numbering';
        $whatPrints = 'What prints';

        return [
            'invoice_business_name' => ['label' => 'Business name', 'kind' => 'text', 'group' => 'letterhead', 'group_title' => $letterhead, 'scope' => $both,
                'hint' => 'Shown at the top of every document.'],
            'invoice_business_address' => ['label' => 'Registered address', 'kind' => 'textarea', 'group' => 'letterhead', 'group_title' => $letterhead, 'scope' => $both],
            'invoice_business_email' => ['label' => 'Contact email', 'kind' => 'text', 'group' => 'letterhead', 'group_title' => $letterhead, 'scope' => $both],
            'invoice_business_phone' => ['label' => 'Contact phone', 'kind' => 'text', 'group' => 'letterhead', 'group_title' => $letterhead, 'scope' => $both],
            'invoice_tax_id_label' => ['label' => 'Tax ID label', 'kind' => 'text', 'group' => 'letterhead', 'group_title' => $letterhead, 'scope' => $both,
                'hint' => 'For example GSTIN, VAT, ABN.'],
            'invoice_tax_id' => ['label' => 'Tax ID', 'kind' => 'text', 'group' => 'letterhead', 'group_title' => $letterhead, 'scope' => $both,
                'hint' => 'Only printed when both this and its label are filled in.'],
            'invoice_logo_url' => ['label' => 'Logo', 'kind' => 'image', 'group' => 'letterhead', 'group_title' => $letterhead, 'scope' => $both,
                'hint' => 'PNG, JPEG, SVG or WebP, up to 5 MB. Printed in the letterhead, so a wide mark works best.'],
            'invoice_accent_color' => ['label' => 'Accent colour', 'kind' => 'color', 'group' => 'letterhead', 'group_title' => $letterhead, 'scope' => $both,
                'hint' => 'Used for rules, headings and the balance due.'],

            'invoice_number_prefix' => ['label' => 'Invoice number prefix', 'kind' => 'text', 'group' => 'numbering', 'group_title' => $numbering, 'scope' => $invoice,
                'hint' => 'Letters and digits only.'],
            'invoice_number_padding' => ['label' => 'Sequence digits', 'kind' => 'number', 'group' => 'numbering', 'group_title' => $numbering, 'scope' => $invoice,
                'hint' => 'Zero padding on the running number.'],

            'invoice_footer_note' => ['label' => 'Footer note', 'kind' => 'textarea', 'group' => 'sections', 'group_title' => $whatPrints, 'scope' => $invoice],
            'invoice_show_provider' => ['label' => 'Provider name', 'kind' => 'switch', 'group' => 'sections', 'group_title' => $whatPrints, 'scope' => $invoice],
            'invoice_show_duration_column' => ['label' => 'Duration column', 'kind' => 'switch', 'group' => 'sections', 'group_title' => $whatPrints, 'scope' => $invoice],
            'invoice_show_balance_due' => ['label' => 'Balance due line', 'kind' => 'switch', 'group' => 'sections', 'group_title' => $whatPrints, 'scope' => $invoice],

            // These four read as customer switches but print on both documents.
            'invoice_show_logo' => ['label' => 'Logo', 'kind' => 'switch', 'group' => 'sections', 'group_title' => $whatPrints, 'scope' => $both],
            'invoice_show_business_address' => ['label' => 'Registered address', 'kind' => 'switch', 'group' => 'sections', 'group_title' => $whatPrints, 'scope' => $both],
            'invoice_show_tax_id' => ['label' => 'Tax ID', 'kind' => 'switch', 'group' => 'sections', 'group_title' => $whatPrints, 'scope' => $both],
            'invoice_show_terms' => ['label' => 'Terms and conditions', 'kind' => 'switch', 'group' => 'sections', 'group_title' => $whatPrints, 'scope' => $both],
            'invoice_terms' => ['label' => 'Terms and conditions', 'kind' => 'textarea', 'group' => 'sections', 'group_title' => $whatPrints, 'scope' => $both,
                'hint' => 'One set of terms, printed on both documents. A settlement is a record of money paid, so anything promising a customer a refund belongs on the invoice only.'],

            'settlement_invoice_number_prefix' => ['label' => 'Settlement prefix', 'kind' => 'text', 'group' => 'numbering', 'group_title' => $numbering, 'scope' => $settlement,
                'hint' => 'Letters and digits only. Kept separate from the customer invoice series so an owner quoting a settlement cannot be mistaken for a customer.'],
            'settlement_invoice_number_padding' => ['label' => 'Sequence digits', 'kind' => 'number', 'group' => 'numbering', 'group_title' => $numbering, 'scope' => $settlement,
                'hint' => 'Zero padding on the running settlement number.'],
            'settlement_invoice_document_title' => ['label' => 'Document title', 'kind' => 'text', 'group' => 'sections', 'group_title' => $whatPrints, 'scope' => $settlement,
                'hint' => 'Printed where the customer invoice reads "Invoice".'],
            'settlement_invoice_footer_note' => ['label' => 'Footer note', 'kind' => 'textarea', 'group' => 'sections', 'group_title' => $whatPrints, 'scope' => $settlement,
                'hint' => 'A separate note from the customer one — "thank you for booking" makes no sense on a commission statement.'],
            'settlement_invoice_show_billed_revenue' => ['label' => 'Total billed by the salon', 'kind' => 'switch', 'group' => 'sections', 'group_title' => $whatPrints, 'scope' => $settlement],
            'settlement_invoice_show_appointments_count' => ['label' => 'Completed appointment count', 'kind' => 'switch', 'group' => 'sections', 'group_title' => $whatPrints, 'scope' => $settlement],
        ];
    }

    /**
     * Plain descriptions of what each setting does, stored alongside the value
     * and shown in the audit log.
     *
     * These are written from a reader's point of view, so they name the document
     * the change reaches. An audit entry that says "address printed on every
     * invoice" is no use to whoever later asks why the settlement statements
     * changed too.
     *
     * @return array<string, string>
     */
    private function invoiceDescriptions(): array
    {
        $both = 'both documents';
        $invoice = 'the customer invoice';
        $settlement = 'settlement statements';

        return [
            'invoice_business_name' => "Business name in the letterhead on $both",
            'invoice_business_address' => "Registered address, printed on $both",
            'invoice_business_email' => 'Contact email on '.$both,
            'invoice_business_phone' => 'Contact phone on '.$both,
            'invoice_tax_id' => 'Tax identity number, printed on '.$both,
            'invoice_tax_id_label' => 'Label printed before the tax identity number on '.$both,
            'invoice_logo_url' => 'Logo shown in the letterhead on '.$both,
            'invoice_accent_color' => 'Accent colour used for rules and headings on '.$both,
            'invoice_footer_note' => "Short note at the foot of $invoice",
            'invoice_terms' => "Terms and conditions printed on $both",
            'invoice_number_prefix' => "Letters and digits placed before the $invoice number",
            'invoice_number_padding' => "Zero padding applied to the $invoice sequence number",
            'invoice_show_logo' => "Whether the logo is printed on $both",
            'invoice_show_business_address' => "Whether the registered address is printed on $both",
            'invoice_show_tax_id' => "Whether the tax ID is printed on $both",
            'invoice_show_provider' => "Whether the serving provider is named on $invoice",
            'invoice_show_duration_column' => "Whether the duration column is printed on $invoice",
            'invoice_show_terms' => "Whether terms and conditions are printed on $both",
            'invoice_show_balance_due' => "Whether the balance due line is printed on $invoice",
            'settlement_invoice_number_prefix' => "Letters and digits placed before the settlement number",
            'settlement_invoice_number_padding' => 'Zero padding applied to the settlement sequence number',
            'settlement_invoice_document_title' => 'Title on '.Str::plural('settlement', 2, 'statements').' in place of "Invoice"',
            'settlement_invoice_footer_note' => "Short note at the foot of $settlement",
            'settlement_invoice_show_billed_revenue' => 'Whether the total the salon billed is printed on '.$settlement,
            'settlement_invoice_show_appointments_count' => 'Whether the completed appointment count is printed on '.$settlement,
        ];
    }
}
