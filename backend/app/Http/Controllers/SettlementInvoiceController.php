<?php

namespace App\Http\Controllers;

use App\Models\SettlementInvoice;
use App\Support\InvoiceTemplate;

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
            'settings' => InvoiceTemplate::sanitise($invoice->template ?? []),
        ])->header('X-Robots-Tag', 'noindex, nofollow');
    }
}
