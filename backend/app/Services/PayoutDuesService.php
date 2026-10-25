<?php

namespace App\Services;

use App\Models\PayoutPaymentSubmission;
use App\Models\PlatformPolicySetting;
use App\Models\Salon;
use App\Models\SalonPayout;
use App\Models\User;
use App\Services\Notifications\NotificationService;
use App\Support\Notifications\NotificationType;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

/**
 * A salon paying what a payout says it owes BookALook.
 *
 * Same shape as buying a plan: the owner scans BookALook's QR, pays, and
 * uploads the screenshot; SuperAdmin checks it against the bank and either
 * marks the payout paid — which, for a Commission Model month, renews access —
 * or turns it back with a reason the owner sees.
 *
 * Submitting freezes the payout so the figure the owner paid cannot be
 * recalculated afterwards. Only the full amount settles it: a short payment is
 * rejected with a reason, never half-accepted.
 */
class PayoutDuesService
{
    public function __construct(
        private PayoutService $payouts,
        private NotificationService $notifications,
    ) {
    }

    /**
     * Where to pay BookALook, as the superadmin set it in policy settings.
     * Shared by plan purchases and payout dues.
     *
     * @return array{qr_url: ?string, upi_id: ?string, payee_name: ?string}
     */
    public function paymentDetails(): array
    {
        $blankToNull = fn ($v) => is_string($v) && trim($v) !== '' ? trim($v) : null;

        return [
            'qr_url' => $blankToNull(PlatformPolicySetting::value('payment_qr_url')),
            'upi_id' => $blankToNull(PlatformPolicySetting::value('payment_upi_id')),
            'payee_name' => $blankToNull(PlatformPolicySetting::value('payment_payee_name')),
        ];
    }

    /**
     * The owner's screenshot of paying what the payout owes.
     *
     * @throws \RuntimeException when there is nothing to pay or a payment is already being checked
     */
    public function submit(
        Salon $salon,
        SalonPayout $payout,
        UploadedFile $screenshot,
        ?string $transactionId,
        ?string $note,
        User $owner
    ): PayoutPaymentSubmission {
        // Uploaded before the transaction: a slow upload must not hold a lock,
        // and an upload that fails leaves nothing half-written.
        $path = Storage::disk('cloudinary')->put('payout-payments', $screenshot);
        $url = Storage::disk('cloudinary')->url($path);

        return DB::transaction(function () use ($salon, $payout, $url, $transactionId, $note, $owner) {
            $payout = SalonPayout::whereKey($payout->id)->lockForUpdate()->firstOrFail();

            if ($payout->salon_id !== $salon->id) {
                throw new \RuntimeException('That payout does not belong to this salon.');
            }

            if ($payout->status === PayoutService::STATUS_DISTRIBUTED) {
                throw new \RuntimeException('This payout is already settled.');
            }

            if ((float) $payout->net_amount >= 0) {
                throw new \RuntimeException('There is nothing to pay on this payout — BookALook pays you.');
            }

            $waiting = $payout->paymentSubmissions()
                ->where('status', PayoutPaymentSubmission::STATUS_PENDING)
                ->exists();
            if ($waiting) {
                throw new \RuntimeException('Your payment is already being checked. You will hear back once it is verified.');
            }

            // From here the amount owed is fixed: what they paid against is
            // what will be checked, and anything later goes to next month.
            if (! $payout->locked_at) {
                $payout->forceFill(['locked_at' => now()])->save();
            }

            return PayoutPaymentSubmission::create([
                'salon_payout_id' => $payout->id,
                'salon_id' => $salon->id,
                'amount' => abs((float) $payout->net_amount),
                'screenshot_url' => $url,
                'transaction_id' => $this->clean($transactionId),
                'note' => $this->clean($note),
                'status' => PayoutPaymentSubmission::STATUS_PENDING,
                'submitted_by' => $owner->id,
            ]);
        });
    }

    /**
     * The payment is in the bank: the payout is settled, and a Commission Model
     * month's settlement renews the salon's access.
     */
    public function approve(PayoutPaymentSubmission $submission, User $actor): SalonPayout
    {
        $payout = DB::transaction(function () use ($submission, $actor) {
            $submission = PayoutPaymentSubmission::whereKey($submission->id)->lockForUpdate()->firstOrFail();

            if ($submission->status !== PayoutPaymentSubmission::STATUS_PENDING) {
                throw new \RuntimeException('This payment has already been reviewed.');
            }

            $submission->forceFill([
                'status' => PayoutPaymentSubmission::STATUS_APPROVED,
                'reviewed_by' => $actor->id,
                'reviewed_at' => now(),
            ])->save();

            $reference = $submission->transaction_id
                ?: 'Screenshot '.strtoupper(substr($submission->id, 0, 8));

            return $this->payouts->markDistributed(
                $submission->payout,
                $actor,
                $reference,
                'Paid by the salon via QR; screenshot verified.'
            );
        });

        $this->tellOwner(
            $payout,
            'Payment received',
            sprintf('BookALook has verified your payment of ₹%s for %s. Thank you!', $this->money($submission->amount), $this->cycleName($payout))
        );

        return $payout;
    }

    /**
     * The screenshot does not prove the payment — wrong amount, unreadable,
     * not received. The owner sees why and pays again; the amount owed is
     * unchanged.
     */
    public function reject(PayoutPaymentSubmission $submission, User $actor, string $reason): PayoutPaymentSubmission
    {
        $submission = DB::transaction(function () use ($submission, $actor, $reason) {
            $submission = PayoutPaymentSubmission::whereKey($submission->id)->lockForUpdate()->firstOrFail();

            if ($submission->status !== PayoutPaymentSubmission::STATUS_PENDING) {
                throw new \RuntimeException('This payment has already been reviewed.');
            }

            $submission->forceFill([
                'status' => PayoutPaymentSubmission::STATUS_REJECTED,
                'reviewed_by' => $actor->id,
                'reviewed_at' => now(),
                'rejection_reason' => trim($reason),
            ])->save();

            return $submission;
        });

        $this->tellOwner(
            $submission->payout,
            'Payment not verified',
            sprintf('We could not verify your payment for %s: %s Please pay ₹%s again and upload the new screenshot.',
                $this->cycleName($submission->payout), rtrim(trim($reason), '.').'.', $this->money($submission->amount))
        );

        return $submission;
    }

    private function tellOwner(SalonPayout $payout, string $title, string $message): void
    {
        $salon = $payout->salon;

        try {
            $this->notifications->send(
                $salon?->admin_id,
                NotificationType::GENERAL,
                $title,
                $message,
                ['payout_id' => $payout->id],
                salon: $salon,
            );
        } catch (\Throwable $e) {
            // The payment decision stands whether or not the notice goes out.
            report($e);
        }
    }

    private function cycleName(SalonPayout $payout): string
    {
        return \App\Support\PayoutCycle::label(
            $payout->cycle_type ?? \App\Support\PayoutCycle::WEEKLY,
            \Carbon\Carbon::parse($payout->cycle_start_date),
            \Carbon\Carbon::parse($payout->cycle_end_date)
        );
    }

    private function money(float $amount): string
    {
        return rtrim(rtrim(number_format($amount, 2, '.', ','), '0'), '.');
    }

    private function clean(?string $value): ?string
    {
        $value = $value === null ? null : trim($value);

        return $value === '' ? null : $value;
    }
}
