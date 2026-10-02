<?php

namespace App\Services;

use App\Models\Invoice;
use App\Support\InvoiceTemplate;
use Barryvdh\DomPDF\Facade\Pdf;
use CloudinaryLabs\CloudinaryLaravel\Facades\Cloudinary;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use RuntimeException;
use Throwable;

/**
 * Turns an invoice into a PDF the customer can actually open on a phone.
 *
 * The invoice already has a web page, but a WebView and WhatsApp are different
 * things: a receipt a customer can file, forward to whoever paid them, and open
 * six months later without our server being up is worth more than a link.
 *
 * The result is cached on the invoice. That is not an optimisation — it is a
 * correctness requirement. The figures are frozen at issue time, so a re-render
 * would produce a visually identical file, but it would be a *different* file at
 * a different URL, and a WhatsApp retry would then hand the customer a second
 * copy. One invoice, one URL, forever.
 */
class InvoicePdfService
{
    /** Path prefix. Kept flat so the media library is navigable. */
    private const PREFIX = 'invoices';

    /**
     * A public URL for this invoice's PDF, or null when one cannot be produced.
     *
     * For callers that only want the document if it is there. An invoice is
     * already issued and already visible in the app by the time anyone asks for
     * a PDF of it, so failing to produce one is an operational problem to log
     * and report — never a reason to fail whatever asked.
     *
     * Callers that cannot proceed without the PDF, like the WhatsApp document
     * send, use publish() instead so they can record why it failed.
     */
    public function urlFor(Invoice $invoice): ?string
    {
        try {
            return $this->publish($invoice);
        } catch (Throwable $e) {
            report($e);

            Log::warning('Could not publish invoice PDF', [
                'invoice_id' => $invoice->id,
                'error' => $e->getMessage(),
            ]);

            return null;
        }
    }

    /**
     * A public URL for this invoice's PDF, rendering and uploading it once.
     *
     * Throws with the real cause when the PDF cannot be produced, so the caller
     * can put that cause somewhere a person will read it. Swallowing it here is
     * what used to turn a Cloudinary rejection into AISensy's "Media URL
     * Missing" — an error about the wrong system.
     *
     * Cloudinary rather than local storage because the URL is handed to a
     * third-party messaging provider to fetch, which means it has to be
     * reachable from the public internet on a hostname that is not `localhost`.
     * A file on the app server's disk is invisible to AISensy even when the app
     * itself is perfectly reachable.
     *
     * @throws RuntimeException|Throwable
     */
    public function publish(Invoice $invoice): string
    {
        if (filled($invoice->pdf_url)) {
            return $invoice->pdf_url;
        }

        $pdf = Pdf::loadView('invoices.pdf', [
            'invoice' => $invoice,
            // Frozen onto the invoice at issue time, with defaults filled in.
            // Read from there rather than from the settings table: a reformat
            // must not retroactively restyle a document already sent. Same
            // sanitiser the screen view uses, so the two cannot disagree.
            'settings' => InvoiceTemplate::sanitise($invoice->template ?? []),
        ])->setOptions(self::options())->output();

        $url = $this->upload($pdf, $invoice->invoice_number);

        $invoice->forceFill(['pdf_url' => $url])->save();

        return $url;
    }

    /**
     * Store the PDF on the local public disk and return its URL.
     *
     * We bypass Cloudinary entirely because many newer Cloudinary accounts strictly
     * block Raw (PDF) deliveries by default and omit the toggle from the UI,
     * which causes AISensy to fail with "Media upload error" (401 Unauthorized).
     *
     * Stored on the 'public' disk so it's accessible via the local domain.
     * The URL uses APP_URL from .env, which must be correct for AISensy to reach it.
     */
    private function upload(string $pdf, string $invoiceNumber): string
    {
        $path = self::PREFIX.'/'.$invoiceNumber.'-'.Str::lower(Str::random(8)).'.pdf';
        
        \Illuminate\Support\Facades\Storage::disk('public')->put($path, $pdf);

        return asset('storage/'.$path);
    }


    /**
     * dompdf options, narrowed from its defaults.
     *
     * `isRemoteEnabled` is the one that has to change. SuperAdmin's logo is a
     * remote URL and dompdf refuses remote images outright otherwise, so the
     * letterhead silently disappears from every PDF. The allowance is scoped to
     * exactly what it buys: fetching an image the SuperAdmin configured. Script
     * and foreign-object loading stay off, so a logo hosted somewhere hostile
     * cannot pull in anything else with it.
     *
     * Everything else is left alone. dompdf's defaults are already the safe
     * ones, and overriding them here without a reason would just be a place for
     * the next person to widen the sandbox by accident.
     *
     * @return array<string, mixed>
     */
    private static function options(): array
    {
        return [
            'isRemoteEnabled' => true,
            'isRemoteAllowLocal' => false,
            'isPhpEnabled' => false,
            'isJavascriptEnabled' => false,
            'isHtml5ParserEnabled' => false,
        ];
    }
}
