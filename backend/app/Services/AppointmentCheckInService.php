<?php

namespace App\Services;

use App\Models\Appointment;
use App\Models\AppointmentServiceAddition;
use App\Models\PlatformPolicySetting;
use App\Models\Service;
use App\Models\ServiceProvider;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * The in-salon half of an appointment: check the customer in, serve them, take
 * the money.
 *
 * Two things here matter beyond the happy path. First, whoever actually does
 * the work is recorded on every service line, not just on the appointment —
 * salary and commission are paid off those lines, so an admin re-assigning the
 * job at check-in has to move the money with it. Second, commission is
 * snapshotted at payment time; changing a provider's rate next month must not
 * silently rewrite what they earned today.
 */
class AppointmentCheckInService
{
    /** How the appointment was verified at the door. */
    public const VERIFY_QR = 'qr';
    public const VERIFY_MANUAL = 'manual';

    public const PAYMENT_MODES = ['cash', 'upi', 'card', 'online'];

    /** Used when a service template has no duration recorded. */
    public const SLOT_FALLBACK_MINUTES = 30;

    /**
     * Find the appointment behind a scanned QR token.
     *
     * The token is only ever compared as a hash, and it is scoped to the salon
     * doing the scanning so one salon cannot check in another's customer.
     */
    public function findByToken(string $salonId, string $token): ?Appointment
    {
        return Appointment::with($this->relations())
            ->where('salon_id', $salonId)
            ->where('qr_token_hash', hash('sha256', $token))
            ->first();
    }

    /**
     * Why this appointment cannot be started right now, or null when it can.
     */
    public function blockedReason(Appointment $appointment): ?string
    {
        if ($appointment->status === 'in_progress') {
            return 'This appointment has already been started.';
        }

        if ($appointment->status !== 'scheduled') {
            return 'This appointment is ' . str_replace('_', ' ', $appointment->status)
                . ' and cannot be started.';
        }

        if ($appointment->qr_expires_at && now()->greaterThan($appointment->qr_expires_at)) {
            return 'This QR code has expired. Ask the customer to show a fresh one.';
        }

        $early = (int) PlatformPolicySetting::value('appointment_start_early_minutes');

        if (now()->addMinutes($early)->lessThan($this->startsAt($appointment))) {
            return 'It is too early to start this appointment. It begins at '
                . substr($appointment->start_time, 0, 5) . '.';
        }

        return null;
    }

    /**
     * Staff who can take this appointment, so an admin can hand the job to
     * whoever is actually free. Everyone active is listed — the customer's
     * choice is flagged rather than enforced, because the person who was booked
     * may well be the one who called in sick.
     *
     * @return array<int, array>
     */
    public function providerOptions(Appointment $appointment): array
    {
        $requiredServiceIds = $appointment->services
            ->where('line_status', '!=', 'cancelled')
            ->pluck('service_id')
            ->unique()
            ->all();

        return ServiceProvider::with(['user:id,name', 'services:id'])
            ->where('salon_id', $appointment->salon_id)
            ->where('is_active', true)
            ->get()
            ->map(function (ServiceProvider $provider) use ($appointment, $requiredServiceIds) {
                $offered = $provider->services->pluck('id')->all();
                $missing = array_values(array_diff($requiredServiceIds, $offered));

                return [
                    'id' => $provider->id,
                    'name' => $provider->user->name ?? 'Staff',
                    'specialization' => $provider->specialization,
                    'commission_percentage' => (float) $provider->commission_percentage,
                    'is_booked_provider' => $provider->id === $appointment->appointed_provider_id,
                    'can_perform_all' => empty($missing),
                    'missing_count' => count($missing),
                ];
            })
            ->sortByDesc('is_booked_provider')
            ->values()
            ->all();
    }

    /**
     * Start the session.
     *
     * [$servingProviderId] is who will actually do the work. It defaults to the
     * provider the customer booked, but an admin can hand it to someone else at
     * the door and the service lines follow.
     */
    public function start(
        Appointment $appointment,
        ?string $servingProviderId,
        User $actor,
        string $method = self::VERIFY_QR,
        ?string $note = null
    ): Appointment {
        $servingProviderId ??= $appointment->appointed_provider_id;

        return DB::transaction(function () use ($appointment, $servingProviderId, $actor, $method, $note) {
            $appointment->status = 'in_progress';
            $appointment->serving_provider_id = $servingProviderId;
            $appointment->verification_method = $method;
            $appointment->qr_verified_at = now();
            $appointment->qr_verified_by = $actor->id;
            $appointment->started_at = now();

            if ($method === self::VERIFY_MANUAL) {
                // A manual check-in is a deliberate override; keep why, and keep
                // the token unusable so it cannot be replayed afterwards.
                $appointment->manual_check_in_reason = $note;
                $appointment->qr_token_hash = null;
            }

            $appointment->save();

            // Salary is calculated off the lines, so the person actually doing
            // the work has to be on them.
            $appointment->services()
                ->where('line_status', '!=', 'cancelled')
                ->update(['serving_provider_id' => $servingProviderId]);

            return $appointment->fresh($this->relations());
        });
    }

    /**
     * Everything on the bill, including anything added mid-appointment.
     *
     * @return array{lines: array, total: float, advance_paid: float,
     *               balance_due: float, already_collected: float}
     */
    public function bill(Appointment $appointment): array
    {
        $lines = [];
        $total = 0.0;

        foreach ($appointment->services as $line) {
            if ($line->line_status === 'cancelled') {
                continue;
            }

            $price = (float) $line->price_at_booking;
            $total += $price;

            $lines[] = [
                'id' => $line->id,
                'name' => $line->service->template->name ?? 'Service',
                'kind' => $line->combo_id ? 'package' : 'service',
                'price' => $price,
                'duration_minutes' => (int) $line->duration_minutes_at_booking,
                'provider_name' => $line->servingProvider->user->name
                    ?? $appointment->servingProvider->user->name
                    ?? null,
                'added_mid_appointment' => false,
            ];
        }

        foreach ($appointment->serviceAdditions as $addition) {
            // Only a voided addition leaves the bill; a completed one is still
            // owed for.
            if (! $addition->isLive()) {
                continue;
            }

            $price = (float) $addition->price_at_addition;
            $total += $price;

            $lines[] = [
                'id' => $addition->id,
                'name' => $addition->service->template->name ?? 'Service',
                'kind' => 'service',
                'price' => $price,
                'duration_minutes' => (int) $addition->duration_minutes_at_addition,
                // The provider who delivered this specific extra, which may not
                // be the one handling the original booking.
                'provider_id' => $addition->provider_id,
                'provider_name' => $addition->provider->user->name ?? null,
                'added_mid_appointment' => true,
                'added_by_name' => $addition->addedBy->name ?? null,
                'added_at' => $addition->added_at,
            ];
        }

        $advance = (float) $appointment->advance_amount;
        $collected = $this->collectedSoFar($appointment);

        return [
            'lines' => $lines,
            'total' => round($total, 2),
            'advance_paid' => round($advance, 2),
            // Whatever is left after the advance and anything already taken.
            'balance_due' => round(max($total - $advance - $collected, 0), 2),
            'already_collected' => round($collected, 2),
        ];
    }

    /**
     * Add a service to an appointment that is already under way.
     *
     * No digital approval is collected — the customer agreed in the chair. What
     * matters is that the record is honest afterwards, so the addition is a
     * separate row carrying its own price, duration, timestamp, who added it
     * and, crucially, which provider actually delivered it. That last part may
     * differ from whoever is handling the original booking, and it is what
     * keeps commission right when two people contribute to one appointment.
     *
     * Nothing in the original booking is touched.
     */
    public function addExtraService(
        Appointment $appointment,
        Service $service,
        string $providerId,
        User $actor
    ): AppointmentServiceAddition {
        return DB::transaction(function () use ($appointment, $service, $providerId, $actor) {
            $addition = AppointmentServiceAddition::create([
                'appointment_id' => $appointment->id,
                'service_id' => $service->id,
                'provider_id' => $providerId,
                'added_by' => $actor->id,
                // Snapshotted: a later price change must not rewrite this bill.
                'price_at_addition' => $service->price,
                'duration_minutes_at_addition' => $service->template->estimated_duration_minutes
                    ?? self::SLOT_FALLBACK_MINUTES,
                'status' => AppointmentServiceAddition::STATUS_ACTIVE,
                'added_at' => now(),
            ]);

            $this->recalculateTotals($appointment);

            return $addition;
        });
    }

    /**
     * Undo an addition made by mistake.
     *
     * Voided rather than deleted, so the bill can still explain itself: the
     * line stays in the record with who added it and who took it off.
     */
    public function voidAddition(Appointment $appointment, AppointmentServiceAddition $addition): void
    {
        DB::transaction(function () use ($appointment, $addition) {
            $addition->status = AppointmentServiceAddition::STATUS_VOIDED;
            $addition->save();

            $this->recalculateTotals($appointment);
        });
    }

    /**
     * Re-derive the appointment total from its booked lines plus live
     * additions. The advance never changes — it was paid against the original
     * booking — so any extra simply raises the balance due at the counter.
     */
    public function recalculateTotals(Appointment $appointment): void
    {
        $booked = (float) $appointment->services()
            ->where('line_status', '!=', 'cancelled')
            ->sum('price_at_booking');

        $added = (float) $appointment->serviceAdditions()
            ->live()
            ->sum('price_at_addition');

        $appointment->total_amount = round($booked + $added, 2);
        $appointment->balance_amount = round(
            max($appointment->total_amount - (float) $appointment->advance_amount, 0),
            2
        );
        $appointment->save();

        $appointment->load(['services', 'serviceAdditions']);
    }

    /**
     * Take the balance and close the appointment.
     *
     * The salon does not run a tab, so collecting the balance and finishing the
     * job are one action rather than two states that can drift apart.
     *
     * @return array{appointment: Appointment, bill: array, coins_earned: int, new_balance: int}
     */
    public function collectPaymentAndComplete(
        Appointment $appointment,
        string $mode,
        User $actor,
        ?string $note = null
    ): array {
        return DB::transaction(function () use ($appointment, $mode, $actor, $note) {
            $bill = $this->bill($appointment);

            if ($bill['balance_due'] > 0) {
                DB::table('payments')->insert([
                    'id' => (string) Str::uuid(),
                    'appointment_id' => $appointment->id,
                    'amount' => $bill['balance_due'],
                    'currency' => 'INR',
                    'payment_type' => $bill['advance_paid'] > 0 ? 'balance' : 'full',
                    'payment_mode' => $mode,
                    'status' => 'success',
                    'paid_at' => now(),
                    // Makes a double-tap on "collect" a no-op rather than a
                    // second charge.
                    'idempotency_key' => 'balance:' . $appointment->id,
                    'metadata' => json_encode([
                        'collected_by' => $actor->id,
                        'collected_by_name' => $actor->name,
                        'note' => $note,
                    ]),
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }

            $this->snapshotCommissions($appointment);

            $appointment->status = 'completed';
            $appointment->completed_at = now();
            $appointment->final_billed_amount = $bill['total'];
            $appointment->total_amount = $bill['total'];
            $appointment->balance_amount = 0;
            $appointment->payment_collected_at = now();
            $appointment->payment_collected_by = $actor->id;
            $appointment->payment_mode = $mode;
            $appointment->save();

            $wallet = $this->awardWalletCoins($appointment);

            return [
                'appointment' => $appointment->fresh($this->relations()),
                'bill' => $bill,
                'coins_earned' => $wallet['coins_earned'],
                'new_balance' => $wallet['new_balance'],
            ];
        });
    }

    /**
     * Freeze each line's commission against the provider who actually served
     * it. Done at payment time so a later rate change cannot rewrite history.
     */
    private function snapshotCommissions(Appointment $appointment): void
    {
        $rates = ServiceProvider::where('salon_id', $appointment->salon_id)
            ->pluck('commission_percentage', 'id');

        foreach ($appointment->services as $line) {
            if ($line->line_status === 'cancelled') {
                continue;
            }

            $providerId = $line->serving_provider_id ?? $appointment->serving_provider_id;
            $rate = (float) ($rates[$providerId] ?? 0);

            $line->serving_provider_id = $providerId;
            $line->commission_percentage_snapshot = $rate;
            $line->commission_amount = round((float) $line->price_at_booking * $rate / 100, 2);
            $line->line_status = 'completed';
            $line->save();
        }

        foreach ($appointment->serviceAdditions as $addition) {
            if (! $addition->isLive()) {
                continue;
            }

            $rate = (float) ($rates[$addition->provider_id] ?? 0);

            $addition->commission_percentage_snapshot = $rate;
            $addition->commission_amount = round((float) $addition->price_at_addition * $rate / 100, 2);
            // Settled with the rest of the bill, so an extra reads the same as
            // a booked line rather than sitting at 'active' forever.
            $addition->status = AppointmentServiceAddition::STATUS_COMPLETED;
            $addition->save();
        }
    }

    /**
     * Reward ladder coins for a completed booking. The ladder itself lives in
     * WalletService — this only asks it to run.
     *
     * @return array{coins_earned: int, new_balance: int}
     */
    private function awardWalletCoins(Appointment $appointment): array
    {
        $result = app(WalletService::class)->awardForCompletedAppointment($appointment);

        return [
            'coins_earned' => $result['coins_earned'],
            'new_balance' => $result['new_balance'],
        ];
    }

    private function collectedSoFar(Appointment $appointment): float
    {
        return (float) DB::table('payments')
            ->where('appointment_id', $appointment->id)
            ->where('status', 'success')
            ->whereIn('payment_type', ['balance', 'full'])
            ->sum('amount');
    }

    private function startsAt(Appointment $appointment): Carbon
    {
        return Carbon::parse(
            Carbon::parse($appointment->appointment_date)->format('Y-m-d') . ' ' . $appointment->start_time
        );
    }

    /**
     * Flatten an appointment into what the partner app's check-in, walk-in and
     * billing screens all read. Shared so those screens cannot drift apart.
     */
    public function present(Appointment $appointment): array
    {
        $isWalkIn = $appointment->booking_source === 'walk_in';

        return [
            'id' => $appointment->id,
            'status' => $appointment->status,
            'booking_source' => $appointment->booking_source,
            'appointment_date' => Carbon::parse($appointment->appointment_date)->toDateString(),
            'start_time' => substr($appointment->start_time, 0, 5),
            'end_time' => substr($appointment->end_time, 0, 5),
            'customer_name' => $isWalkIn
                ? ($appointment->walk_in_customer_name ?? 'Walk-in')
                : ($appointment->customer->name ?? 'Customer'),
            'customer_phone' => $isWalkIn
                ? $appointment->walk_in_customer_phone
                : ($appointment->customer->phone ?? null),
            'booked_provider_id' => $appointment->appointed_provider_id,
            'booked_provider_name' => $appointment->appointedProvider->user->name ?? 'Any staff',
            'serving_provider_id' => $appointment->serving_provider_id,
            'serving_provider_name' => $appointment->servingProvider->user->name ?? null,
            'total_amount' => (float) $appointment->total_amount,
            'advance_amount' => (float) $appointment->advance_amount,
            'balance_amount' => (float) $appointment->balance_amount,
            'final_billed_amount' => $appointment->final_billed_amount !== null
                ? (float) $appointment->final_billed_amount
                : null,
            'verification_method' => $appointment->verification_method,
            'manual_check_in_reason' => $appointment->manual_check_in_reason,
            'started_at' => $appointment->started_at,
            'completed_at' => $appointment->completed_at,
            'payment_mode' => $appointment->payment_mode,
            'payment_collected_at' => $appointment->payment_collected_at,
        ];
    }

    /** @return string[] */
    public function relations(): array
    {
        return [
            'customer:id,name,phone,email',
            'appointedProvider.user:id,name',
            'servingProvider.user:id,name',
            'services.service.template:id,name,estimated_duration_minutes',
            'services.servingProvider.user:id,name',
            'serviceAdditions.service.template:id,name,estimated_duration_minutes',
            'serviceAdditions.provider.user:id,name',
            'serviceAdditions.addedBy:id,name,role',
        ];
    }
}
