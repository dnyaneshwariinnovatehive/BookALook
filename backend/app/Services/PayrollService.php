<?php

namespace App\Services;

use App\Models\AppointmentService as AppointmentLine;
use App\Models\AppointmentServiceAddition;
use App\Models\ProviderLeave;
use App\Models\ProviderWorkingHour;
use App\Models\SalaryPayout;
use App\Models\ServiceProvider;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Monthly pay for salon staff.
 *
 *     payable = base salary − unpaid leave + commission earned
 *
 * Commission is read from the snapshots written when each appointment was paid
 * for, never recomputed from today's rates — a payslip has to keep saying the
 * same thing after a raise. It is credited per service line, so a colleague who
 * delivered one service mid-appointment is paid for that line and not for the
 * rest of the appointment.
 */
class PayrollService
{
    /**
     * Commission a provider earned in a month.
     *
     * Two sources, both already snapshotted at payment time: the booked service
     * lines they served, and services added mid-appointment that were assigned
     * to them. Only completed appointments count.
     */
    public function commissionEarned(string $providerId, Carbon $month): float
    {
        [$from, $to] = $this->monthBounds($month);

        $onBookedLines = (float) AppointmentLine::query()
            ->join('appointments', 'appointments.id', '=', 'appointment_services.appointment_id')
            ->where('appointment_services.serving_provider_id', $providerId)
            ->where('appointment_services.line_status', '!=', 'cancelled')
            ->where('appointments.status', 'completed')
            ->whereBetween('appointments.appointment_date', [$from->toDateString(), $to->toDateString()])
            ->sum('appointment_services.commission_amount');

        $onAdditions = (float) AppointmentServiceAddition::query()
            ->join('appointments', 'appointments.id', '=', 'appointment_service_additions.appointment_id')
            ->where('appointment_service_additions.provider_id', $providerId)
            ->whereIn('appointment_service_additions.status', AppointmentServiceAddition::LIVE_STATUSES)
            ->where('appointments.status', 'completed')
            ->whereBetween('appointments.appointment_date', [$from->toDateString(), $to->toDateString()])
            ->sum('appointment_service_additions.commission_amount');

        return round($onBookedLines + $onAdditions, 2);
    }

    /**
     * The individual service lines behind that number, so a staff member can
     * check their own payslip rather than take it on trust.
     *
     * @return array<int, array>
     */
    public function commissionBreakdown(string $providerId, Carbon $month): array
    {
        [$from, $to] = $this->monthBounds($month);

        $booked = AppointmentLine::with(['service.template:id,name', 'appointment:id,appointment_date,booking_source'])
            ->join('appointments', 'appointments.id', '=', 'appointment_services.appointment_id')
            ->where('appointment_services.serving_provider_id', $providerId)
            ->where('appointment_services.line_status', '!=', 'cancelled')
            ->where('appointments.status', 'completed')
            ->whereBetween('appointments.appointment_date', [$from->toDateString(), $to->toDateString()])
            ->where('appointment_services.commission_amount', '>', 0)
            ->select('appointment_services.*')
            ->get()
            ->map(fn (AppointmentLine $line) => [
                'date' => Carbon::parse($line->appointment->appointment_date)->toDateString(),
                'service' => $line->service->template->name ?? 'Service',
                'source' => $line->appointment->booking_source,
                'charged' => (float) $line->price_at_booking,
                'rate' => (float) $line->commission_percentage_snapshot,
                'commission' => (float) $line->commission_amount,
                'added_mid_appointment' => false,
            ]);

        $added = AppointmentServiceAddition::with(['service.template:id,name', 'appointment:id,appointment_date,booking_source'])
            ->join('appointments', 'appointments.id', '=', 'appointment_service_additions.appointment_id')
            ->where('appointment_service_additions.provider_id', $providerId)
            ->whereIn('appointment_service_additions.status', AppointmentServiceAddition::LIVE_STATUSES)
            ->where('appointments.status', 'completed')
            ->whereBetween('appointments.appointment_date', [$from->toDateString(), $to->toDateString()])
            ->where('appointment_service_additions.commission_amount', '>', 0)
            ->select('appointment_service_additions.*')
            ->get()
            ->map(fn (AppointmentServiceAddition $addition) => [
                'date' => Carbon::parse($addition->appointment->appointment_date)->toDateString(),
                'service' => $addition->service->template->name ?? 'Service',
                'source' => $addition->appointment->booking_source,
                'charged' => (float) $addition->price_at_addition,
                'rate' => (float) $addition->commission_percentage_snapshot,
                'commission' => (float) $addition->commission_amount,
                'added_mid_appointment' => true,
            ]);

        return $booked->concat($added)->sortBy('date')->values()->all();
    }

    /**
     * Days this provider was rostered to work in the month.
     *
     * Their own weekly-off pattern, not the salon's — someone rostered five
     * days a week loses more per day of unpaid leave than a colleague rostered
     * six, which is the fair reading of a monthly salary.
     */
    public function workingDaysInMonth(string $providerId, Carbon $month): int
    {
        [$from, $to] = $this->monthBounds($month);

        $offDays = ProviderWorkingHour::where('provider_id', $providerId)
            ->where('is_weekly_off', true)
            ->pluck('day_of_week')
            ->all();

        // No roster recorded: fall back to every calendar day, which never
        // over-deducts.
        $rostered = ProviderWorkingHour::where('provider_id', $providerId)->exists();

        if (! $rostered) {
            return $from->daysInMonth;
        }

        $days = 0;

        for ($date = $from->copy(); $date->lte($to); $date->addDay()) {
            if (! in_array($date->dayOfWeek, $offDays, true)) {
                $days++;
            }
        }

        // Guard against a provider marked off every day, which would otherwise
        // divide by zero.
        return max($days, 1);
    }

    /**
     * Approved leave in the month, split by whether it costs anything.
     *
     * @return array{paid: float, unpaid: float}
     */
    public function leaveDays(string $providerId, Carbon $month): array
    {
        [$from, $to] = $this->monthBounds($month);

        $leaves = ProviderLeave::where('provider_id', $providerId)
            ->where('status', ProviderLeave::STATUS_APPROVED)
            ->whereBetween('leave_date', [$from->toDateString(), $to->toDateString()])
            ->get();

        return [
            'paid' => round($leaves->where('leave_type', ProviderLeave::TYPE_PAID)
                ->sum(fn (ProviderLeave $l) => $l->dayFraction()), 1),
            'unpaid' => round($leaves->where('leave_type', ProviderLeave::TYPE_UNPAID)
                ->sum(fn (ProviderLeave $l) => $l->dayFraction()), 1),
        ];
    }

    /**
     * Build or refresh a month's pay record.
     *
     * A month already marked paid is left alone — the money has gone and the
     * payslip has to keep matching it.
     */
    public function build(ServiceProvider $provider, Carbon $month): SalaryPayout
    {
        $monthStart = $month->copy()->startOfMonth();

        $existing = SalaryPayout::where('provider_id', $provider->id)
            ->whereDate('salary_month', $monthStart->toDateString())
            ->first();

        if ($existing && $existing->isPaid()) {
            return $existing;
        }

        $base = (float) $provider->base_salary;
        $workingDays = $this->workingDaysInMonth($provider->id, $monthStart);
        $dailyRate = round($base / $workingDays, 2);

        $leave = $this->leaveDays($provider->id, $monthStart);
        $deduction = round($dailyRate * $leave['unpaid'], 2);

        $commission = $this->commissionEarned($provider->id, $monthStart);
        $adjustments = (float) ($existing->other_adjustments ?? 0);

        $payable = round(max($base - $deduction, 0) + $commission + $adjustments, 2);

        $payout = SalaryPayout::updateOrCreate(
            [
                'provider_id' => $provider->id,
                'salary_month' => $monthStart->toDateString(),
            ],
            [
                'salon_id' => $provider->salon_id,
                'base_salary_snapshot' => $base,
                'commission_percentage_snapshot' => (float) $provider->commission_percentage,
                'commission_earned' => $commission,
                'working_days_in_month' => $workingDays,
                'daily_rate' => $dailyRate,
                'paid_leave_days' => $leave['paid'],
                'unpaid_leave_days' => $leave['unpaid'],
                'unpaid_leave_deduction' => $deduction,
                'other_adjustments' => $adjustments,
                'total_payable' => $payable,
                'status' => $existing->status ?? SalaryPayout::STATUS_PENDING,
                'calculated_at' => now(),
            ]
        );

        return $payout->fresh();
    }

    /**
     * Rebuild every active staff member's record for a month.
     *
     * @return array<int, SalaryPayout>
     */
    public function buildForSalon(string $salonId, Carbon $month): array
    {
        $providers = ServiceProvider::where('salon_id', $salonId)
            ->where('is_active', true)
            ->get();

        return DB::transaction(
            fn () => $providers->map(fn (ServiceProvider $p) => $this->build($p, $month))->all()
        );
    }

    public function markPaid(SalaryPayout $payout, User $actor, ?string $reference = null): SalaryPayout
    {
        $payout->forceFill([
            'status' => SalaryPayout::STATUS_PAID,
            'paid_by' => $actor->id,
            'paid_at' => now(),
            'payment_reference' => $reference,
        ])->save();

        return $payout->fresh();
    }

    /**
     * Undo a payment marked in error. The figures are left as they were so the
     * record does not silently change underneath the correction.
     */
    public function markUnpaid(SalaryPayout $payout): SalaryPayout
    {
        $payout->forceFill([
            'status' => SalaryPayout::STATUS_PENDING,
            'paid_by' => null,
            'paid_at' => null,
            'payment_reference' => null,
        ])->save();

        return $payout->fresh();
    }

    /**
     * The payslip, with every component that produced the total.
     */
    public function present(SalaryPayout $payout, bool $withBreakdown = false): array
    {
        $month = Carbon::parse($payout->salary_month);

        $payslip = [
            'id' => $payout->id,
            'provider_id' => $payout->provider_id,
            'provider_name' => $payout->provider->user->name ?? 'Staff',
            'salary_month' => $month->toDateString(),
            'month_label' => $month->format('F Y'),

            'base_salary' => (float) $payout->base_salary_snapshot,
            'working_days_in_month' => (int) $payout->working_days_in_month,
            'daily_rate' => (float) $payout->daily_rate,

            'paid_leave_days' => (float) $payout->paid_leave_days,
            'unpaid_leave_days' => (float) $payout->unpaid_leave_days,
            'unpaid_leave_deduction' => (float) $payout->unpaid_leave_deduction,

            'commission_percentage' => (float) $payout->commission_percentage_snapshot,
            'commission_earned' => (float) $payout->commission_earned,

            'other_adjustments' => (float) $payout->other_adjustments,
            'total_payable' => (float) $payout->total_payable,

            'status' => $payout->status,
            'paid_at' => $payout->paid_at,
            'payment_reference' => $payout->payment_reference,
            'calculated_at' => $payout->calculated_at,
        ];

        if ($withBreakdown) {
            $payslip['commission_lines'] = $this->commissionBreakdown($payout->provider_id, $month);
        }

        return $payslip;
    }

    /** @return array{0: Carbon, 1: Carbon} */
    private function monthBounds(Carbon $month): array
    {
        return [$month->copy()->startOfMonth(), $month->copy()->endOfMonth()];
    }
}
