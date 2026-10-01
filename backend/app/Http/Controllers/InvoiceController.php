<?php

namespace App\Http\Controllers;

use App\Models\Invoice;
use App\Support\InvoiceTemplate;

/**
 * Serves the printable invoice.
 *
 * Reached through a signed link rather than the customer auth middleware,
 * because the thing that opens it is a WebView or a browser, and neither can
 * present a bearer token. Putting the token in the URL instead would leak it
 * into browser history and referrer headers, so the signature carries the proof
 * and the token never leaves the app.
 */
class InvoiceController extends Controller
{
    public function show(Invoice $invoice)
    {
        return response()->view('invoices.show', [
            'invoice' => $invoice,
            // Settings are SuperAdmin-authored, but they are still strings that
            // end up inside a document a customer is about to trust with their
            // money. Anything that could break out of an attribute or a style
            // value is replaced here rather than trusted.
            'settings' => InvoiceTemplate::sanitise($invoice->template ?? []),
        ])->header('X-Robots-Tag', 'noindex, nofollow');
    }
}
