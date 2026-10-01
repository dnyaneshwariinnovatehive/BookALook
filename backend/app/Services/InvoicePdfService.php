<?php

namespace App\Services;

use App\Models\Invoice;
use App\Support\InvoiceTemplate;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
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
    /**
     * The disk the PDFs are published to.
     *
     * Cloudinary rather than local storage because the URL is handed to a
     * third-party messaging provider to fetch, which means it has to be
     * reachable from the public internet on a hostname that is not
     * `localhost`. A file on the app server's disk is invisible to AISensy even
     * when the app itself is perfectly reachable.
     */
    private const DISK = 'cloudinary';

    /** Path prefix. Kept flat so the media library is navigable. */
    private const PREFIX = 'invoices';

    /**
     * A public URL for this invoice's PDF, rendering and uploading it once.
     *
     * Returns null rather than throwing when the disk is unusable. An invoice is
     * already issued and already visible in the app by the time anyone asks for
     * a PDF of it, so failing to produce one is an operational problem to log
     * and report — never a reason to fail the booking that caused the invoice.
     */
    public function urlFor(Invoice $invoice): ?string
    {
        if (filled($invoice->pdf_url)) {
            return $invoice->pdf_url;
        }

        try {
            $disk = Storage::disk(self::DISK);

            $pdf = Pdf::loadView('invoices.pdf', [
                'invoice' => $invoice,
                // Frozen onto the invoice at issue time, with defaults filled in.
                // Read from there rather than from the settings table: a reformat
                // must not retroactively restyle a document already sent. Same
                // sanitiser the screen view uses, so the two cannot disagree.
                'settings' => InvoiceTemplate::sanitise($invoice->template ?? []),
            ])->setOptions(self::options())->output();

            $path = self::PREFIX.'/'.$invoice->invoice_number.'-'.Str::lower(Str::random(8)).'.pdf';

            // Written under a random name on purpose. The invoice number is the
            // predictable part, and a guessable object path is a document
            // anyone can walk through the media library and read.
            //
            // Handed over as a stream rather than as a string of bytes. put() takes
            // a string and every other disk in the app wants contents, but the
            // Cloudinary adapter forwards that string straight into its upload API,
            // which reads a bare string as a *local file path* and calls fopen() on
            // it. A PDF is binary and carries null bytes throughout, so fopen()
            // refuses it and the upload dies with "Argument #1 ($filename) must not
            // contain any null bytes" — an error that reads like a corrupt file
            // rather than a contract mismatch between two libraries, and which
            // mentions nothing about Cloudinary or PDF generation.
            //
            // A resource takes the writeStream() path instead, which the adapter
            // forwards as-is and Cloudinary streams without ever naming a path.
            // The stream is faked from the bytes we already hold, so nothing is
            // spooled to disk in between.
            $stream = fopen('php://temp', 'r+b');

            if ($stream === false) {
                Log::warning('Could not open a stream for the invoice PDF', ['invoice_id' => $invoice->id]);

                return null;
            }

            try {
                fwrite($stream, $pdf);
                rewind($stream);

                $stored = $disk->put($path, $stream);
            } finally {
                if (is_resource($stream)) {
                    fclose($stream);
                }
            }

            if (! $stored) {
                Log::warning('Invoice PDF upload returned false', [
                    'invoice_id' => $invoice->id,
                    'path' => $path,
                ]);

                return null;
            }

            $url = $disk->url($path);

            $invoice->forceFill(['pdf_url' => $url])->save();

            return $url;
        } catch (Throwable $e) {
            report($e);

            Log::warning('Could not render invoice PDF', [
                'invoice_id' => $invoice->id,
                'error' => $e->getMessage(),
            ]);

            return null;
        }
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