<?php

namespace App\Http\Controllers;

use App\Models\SettlementInvoice;

/**
 * Serves the printable settlement invoice.
 *
 * Reached through a signed link rather than the auth middleware, because the
 * thing that opens it is the owner's phone browser, which cannot present a
 * bearer token. Putting the token in the URL instead would leak it into browser
 * history and referrer headers, so the signature carries the proof and the token
 * never leaves the app. Same contract as the customer invoice.
 */
class SettlementInvoiceController extends Controller
{
    public function show(SettlementInvoice $invoice)
    {
        return response()->view('settlement-invoices.show', [
            'invoice' => $invoice,
            // Settings are SuperAdmin-authored, but they are still strings that
            // end up inside a document describing someone's money. Anything
            // that could break out of an attribute or a style value is replaced
            // here rather than trusted.
            'settings' => $this->safeTemplate($invoice->template ?? []),
        ])->header('X-Robots-Tag', 'noindex, nofollow');
    }

    /**
     * @return array<string, mixed>
     */
    private function safeTemplate(array $template): array
    {
        $out = $template;

        foreach (['invoice_business_name', 'invoice_business_address', 'invoice_business_email',
            'invoice_business_phone', 'invoice_tax_id', 'invoice_tax_id_label',
            'invoice_footer_note', 'invoice_terms', 'settlement_invoice_document_title',
            'settlement_invoice_footer_note'] as $key) {
            $out[$key] = (string) ($template[$key] ?? '');
        }

        // A colour is only ever a hex triple, so anything else is not a colour
        // and falls back rather than being interpolated into a stylesheet.
        $accent = (string) ($template['invoice_accent_color'] ?? '');
        $out['invoice_accent_color'] = preg_match('/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/', $accent)
            ? $accent
            : '#B08D57';

        // An <img src> is an injection point as much as a URL is, so only the
        // schemes that can actually serve an image are allowed through.
        $logo = (string) ($template['invoice_logo_url'] ?? '');
        $out['invoice_logo_url'] = preg_match('#^(https?://|/)#i', $logo) ? $logo : '';

        // Every switch is coerced to a real boolean. A missing or odd value must
        // never decide whether a section prints by accident.
        foreach (['invoice_show_logo', 'invoice_show_business_address', 'invoice_show_tax_id',
            'invoice_show_terms', 'settlement_invoice_show_billed_revenue',
            'settlement_invoice_show_appointments_count'] as $key) {
            $out[$key] = filter_var($template[$key] ?? false, FILTER_VALIDATE_BOOLEAN);
        }

        return $out;
    }
}
