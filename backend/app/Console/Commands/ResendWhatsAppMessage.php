<?php

namespace App\Console\Commands;

use App\Jobs\SendWhatsAppMessageJob;
use App\Models\Invoice;
use App\Models\WhatsAppMessage;
use Illuminate\Console\Command;

/**
 * Put failed WhatsApp messages back in the queue once their cause is fixed.
 *
 * Nothing else will. The send job only acts on `queued` rows, and the outbox
 * drain only claims rows no provider has tried — both deliberately, so a retry
 * can never put two copies in a customer's chat. A `failed` row therefore stays
 * failed until somebody decides it should go again, which is this command.
 *
 * A booking confirmation that failed for want of its invoice PDF still names
 * the invoice as its attachment, so a resend renders and uploads it afresh.
 */
class ResendWhatsAppMessage extends Command
{
    protected $signature = 'app:resend-whatsapp
                            {message? : Id of a failed WhatsApp message}
                            {--invoice= : Resend the failed messages for this invoice number, e.g. BAL-2026-00012}
                            {--dry-run : List what would be resent without sending anything}';

    protected $description = 'Re-queue failed WhatsApp messages by message id or invoice number';

    public function handle(): int
    {
        $query = WhatsAppMessage::query()->where('status', WhatsAppMessage::STATUS_FAILED);

        if ($id = $this->argument('message')) {
            $query->whereKey($id);
        } elseif ($number = $this->option('invoice')) {
            $appointmentId = Invoice::where('invoice_number', $number)->value('appointment_id');

            if (! $appointmentId) {
                $this->error("No invoice numbered {$number}.");

                return self::FAILURE;
            }

            $query->where('related_appointment_id', $appointmentId);
        } else {
            $this->error('Name a message id or pass --invoice=<number>.');

            return self::FAILURE;
        }

        $messages = $query->get();

        if ($messages->isEmpty()) {
            $this->info('No failed messages matched.');

            return self::SUCCESS;
        }

        foreach ($messages as $message) {
            $this->line("{$message->id}  {$message->template}  {$message->to_phone}  — {$message->error}");

            if ($this->option('dry-run')) {
                continue;
            }

            $message->forceFill([
                'status' => WhatsAppMessage::STATUS_QUEUED,
                'failed_at' => null,
                'error' => null,
            ])->save();

            SendWhatsAppMessageJob::dispatch($message->id);
        }

        $this->info(sprintf(
            '%s %d message(s).',
            $this->option('dry-run') ? 'Would resend' : 'Resent',
            $messages->count()
        ));

        return self::SUCCESS;
    }
}
