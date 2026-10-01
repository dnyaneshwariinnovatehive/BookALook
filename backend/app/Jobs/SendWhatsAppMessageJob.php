<?php

namespace App\Jobs;

use App\Models\Appointment;
use App\Models\Invoice;
use App\Models\WhatsAppMessage;
use App\Services\InvoicePdfService;
use App\Services\Notifications\NotificationService;
use App\Services\Notifications\WhatsAppGateway;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use RuntimeException;
use Throwable;

/**
 * Hands one queued outbox row to the configured WhatsApp provider.
 *
 * Every notification that reaches a customer by WhatsApp goes through here rather
 * than being sent from the caller. The reason is the invoice: sending a booking
 * confirmation means rendering a PDF and uploading it, which is far too slow to
 * hold a booking transaction open for, and far too slow to fail a booking over.
 * By the time this runs the booking is committed and the customer already has
 * their in-app notification, so a slow or failed WhatsApp send is a missing
 * message rather than a lost booking.
 *
 * The row is re-read here rather than the model being serialised into the job,
 * so a message that was cancelled, deleted, or already sent in the meantime is
 * skipped instead of sent twice by a retry.
 */
class SendWhatsAppMessageJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    /**
     * Two attempts, spaced out.
     *
     * One is not enough because the failure that actually happens is a network
     * blip against the provider, and that clears on its own. More than two is
     * wasted: the gateway already records a rejected message as `failed` rather
     * than throwing, so a second attempt is only ever for the case where the
     * worker itself died mid-request, not for a message the provider disliked.
     */
    public int $tries = 2;

    /**
     * Wait between attempts. Long enough for a dropped connection to come back,
     * short enough that a retry does not turn a same-day reminder into a
     * next-day one.
     */
    public function backoff(): array
    {
        return [30];
    }

    public function __construct(public string $messageId)
    {
    }

    public function handle(WhatsAppGateway $gateway, InvoicePdfService $pdfs): void
    {
        $message = WhatsAppMessage::find($this->messageId);

        // Sent or failed already, or gone. Either way this job has nothing left
        // to do — the row is the record of what happened, not the queue's.
        if (! $message || $message->status !== WhatsAppMessage::STATUS_QUEUED) {
            return;
        }

        $this->attachInvoice($message, $pdfs);

        $gateway->send($message);
    }

    /**
     * Turn the attachment named on the payload into a real, fetchable document.
     *
     * Done here and not at the call site because rendering and uploading a PDF is
     * slow enough that doing it inline would hold the booking request open, and
     * because the invoice is issued a moment *after* the confirmation notification
     * is written. By the time a job runs, both the invoice and its PDF exist.
     *
     * When the document cannot be produced, nothing is sent. The booking
     * confirmation is a document template, so a send without media is one
     * AISensy is certain to reject — and it used to, with "Media URL Missing",
     * which buried the real cause (a Cloudinary rejection) in the worker log.
     * Throwing instead lets the queue retry a transient upload failure once, and
     * failed() then writes the actual reason onto the row.
     *
     * @throws RuntimeException
     */
    private function attachInvoice(WhatsAppMessage $message, InvoicePdfService $pdfs): void
    {
        $payload = $message->payload ?? [];

        if (($payload['attachment'] ?? null) !== NotificationService::ATTACHMENT_INVOICE) {
            return;
        }

        $invoice = $this->invoiceFor($message);

        if (! $invoice) {
            throw new RuntimeException(
                'No invoice exists for this appointment, so there is no document to attach.'
            );
        }

        try {
            $url = $pdfs->publish($invoice);
        } catch (Throwable $e) {
            throw new RuntimeException(
                "Invoice {$invoice->invoice_number} PDF could not be published: ".$e->getMessage(),
                0,
                $e
            );
        }

        unset($payload['attachment']);

        $payload['media'] = [
            'url' => $url,
            'filename' => $invoice->invoice_number.'.pdf',
        ];

        $message->forceFill(['payload' => $payload])->save();
    }

    /**
     * The invoice behind this message.
     *
     * Looked up through the appointment rather than an id in the payload,
     * deliberately: the payload is written when the confirmation is queued, which
     * is before the invoice exists, so it could not carry an id.
     */
    private function invoiceFor(WhatsAppMessage $message): ?Invoice
    {
        if (! $message->related_appointment_id) {
            return null;
        }

        return Invoice::where('appointment_id', $message->related_appointment_id)->first();
    }

    /**
     * Every attempt failed before the provider was reached.
     *
     * The gateway records its own failures on the row, so the ways to get here
     * are a worker-level fault or an attachment that could not be produced. In
     * both cases the row is still `queued` and would otherwise look like a
     * message merely waiting its turn, so the reason is written onto it. The
     * row is the audit trail; `app:resend-whatsapp` puts it back in the queue
     * once the cause is fixed.
     */
    public function failed(Throwable $e): void
    {
        report($e);

        $message = WhatsAppMessage::whereKey($this->messageId)
            ->where('status', WhatsAppMessage::STATUS_QUEUED)
            ->first();

        $message?->forceFill([
            'status' => WhatsAppMessage::STATUS_FAILED,
            'failed_at' => now(),
            'error' => mb_substr($e->getMessage(), 0, 1000),
        ])->save();
    }
}