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
     * Upload the PDF bytes to Cloudinary as a raw file and return its URL.
     *
     * Three things here are load-bearing, each found in production:
     *
     * 1. The bytes go up as a stream, never as a string. The SDK's
     *    FileUtils::handleFile() treats any string that is not a URL or a
     *    data: URI as a *local file path* and fopen()s it, so PDF bytes fail
     *    with "must not contain any null bytes".
     *
     * 2. The upload carries an explicit `filename`. The SDK names the multipart
     *    file part only from `$options['filename']`, or from basename($file)
     *    when $file is a local path (ApiClient::postFileAsync()). A stream has
     *    no path, and Guzzle will not name a part after a `php://temp` stream,
     *    so without this the PDF goes up as a plain *form field* called `file`.
     *    Cloudinary reads a non-file `file` field as a remote source URL and
     *    rejects it ("Unsupported source URL: %PDF-1.4…" / "Invalid request
     *    parameters"). This is why uploading from a local path works and the
     *    same bytes as a stream do not.
     *
     * 3. The public ID keeps its `.pdf`. For `raw` resources Cloudinary stores
     *    the extension as part of the public ID and has no `format` to add one;
     *    stripping it produced an extensionless URL, which WhatsApp cannot
     *    recognise as a PDF document.
     *
     * Written under a random name. The invoice number is the predictable part,
     * and a guessable object path is a document anyone can walk through the
     * media library and read.
     *
     * Through the SDK rather than Storage::put(): the disk adapter classifies
     * application/pdf as raw, ignores its $options argument (so no filename can
     * be passed), and returns no URL.
     */
    private function upload(string $pdf, string $invoiceNumber): string
    {
        $stream = fopen('php://temp', 'r+b');

        if ($stream === false) {
            throw new RuntimeException('Could not open a temporary stream for the invoice PDF.');
        }

        try {
            fwrite($stream, $pdf);
            rewind($stream);

            $response = Cloudinary::uploadApi()->upload($stream, [
                'public_id' => self::PREFIX.'/'.$invoiceNumber.'-'.Str::lower(Str::random(8)).'.pdf',
                'resource_type' => 'raw',
                'filename' => $invoiceNumber.'.pdf',
            ]);
        } finally {
            if (is_resource($stream)) {
                fclose($stream);
            }
        }

        $url = $response['secure_url'] ?? null;

        // A 200 carrying no URL is the shape of a misconfigured account. Storing
        // an empty pdf_url would cache the invoice as "done" and it would never
        // be retried, so it is a failure like any other.
        if (! is_string($url) || $url === '') {
            throw new RuntimeException('Cloudinary accepted the invoice PDF but returned no URL.');
        }

        return $url;
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
