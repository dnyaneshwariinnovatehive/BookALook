<?php

namespace App\Support;

/**
 * Makes a frozen invoice template safe to interpolate into a document.
 *
 * These values are SuperAdmin-authored strings that end up inside a document a
 * customer is about to trust with their money — as text, as a stylesheet colour,
 * and as an <img src>. Each is an injection point, so each is reduced to the
 * narrowest shape that can still do its job rather than trusted.
 *
 * It lives here rather than in a controller because three renderers now read the
 * same frozen template: the customer invoice page, the settlement statement page,
 * and the PDF that gets sent over WhatsApp. A fourth copy of this whitelist would
 * be one more place to forget a key, and the failure mode is a document that
 * renders a style the author never wrote.
 *
 * The customer and settlement keys are unioned rather than kept apart. The two
 * Blades read disjoint sets, so neither gains or loses a value by being handed
 * the union, and one list cannot drift from the other.
 */
class InvoiceTemplate
{
    /** Cast to string, defaulting to empty rather than to the key. */
    private const STRING_KEYS = [
        'invoice_business_name',
        'invoice_business_address',
        'invoice_business_email',
        'invoice_business_phone',
        'invoice_tax_id',
        'invoice_tax_id_label',
        'invoice_footer_note',
        'invoice_terms',
        'settlement_invoice_document_title',
        'settlement_invoice_footer_note',
    ];

    /** Coerced to real booleans, defaulting to off. */
    private const BOOLEAN_KEYS = [
        'invoice_show_logo',
        'invoice_show_business_address',
        'invoice_show_tax_id',
        'invoice_show_provider',
        'invoice_show_duration_column',
        'invoice_show_terms',
        'invoice_show_balance_due',
        'settlement_invoice_show_billed_revenue',
        'settlement_invoice_show_appointments_count',
    ];

    /** The brand colour, when the stored value is one. */
    private const DEFAULT_ACCENT = '#B08D57';

    /**
     * @param  array<string, mixed>  $template
     * @return array<string, mixed>
     */
    public static function sanitise(array $template): array
    {
        $out = $template;

        foreach (self::STRING_KEYS as $key) {
            $out[$key] = (string) ($template[$key] ?? '');
        }

        foreach (self::BOOLEAN_KEYS as $key) {
            $out[$key] = filter_var($template[$key] ?? false, FILTER_VALIDATE_BOOLEAN);
        }

        // A colour is only ever a hex triple, so anything else is not a colour
        // and falls back rather than being interpolated into a stylesheet.
        $accent = (string) ($template['invoice_accent_color'] ?? '');
        $out['invoice_accent_color'] = preg_match('/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/', $accent)
            ? $accent
            : self::DEFAULT_ACCENT;

        // An <img src> is an injection point as much as a URL is, so only the
        // schemes that can actually serve an image are allowed through.
        $logo = (string) ($template['invoice_logo_url'] ?? '');
        $out['invoice_logo_url'] = preg_match('#^(https?://|/)#i', $logo) ? $logo : '';

        return $out;
    }
}