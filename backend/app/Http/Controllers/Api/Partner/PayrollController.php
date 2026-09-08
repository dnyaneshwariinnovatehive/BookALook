<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\Salon;
use App\Models\SalaryPayout;
use App\Models\SalonPayout;
use App\Models\ServiceProvider;
use App\Services\PayoutService;
use App\Services\PayrollService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

/**
 * Monthly staff pay, and the salon's own view of what the platform settled.
 *
 * Admins see every staff member; a staff member sees only their own payslip,
 * which is the whole point of them being able to check it.
 */
class PayrollController extends Controller
{
    public function __construct(
        private PayrollService $payroll,
        private PayoutService $payouts,
    ) {
    }

    /**
     * Every active staff member's pay for a month.
     */
    public function index(Request $request, $salonId)
    {
        if ($denied = $this->denyUnlessOwner($request, $salonId)) {
            return $denied;
        }

        $month = $this->month($request);

        // Built on read so a newly hired staff member or a late completion
        // shows up without the admin having to remember to press a button.
        $this->payroll->buildForSalon($salonId, $month);

        $payslips = SalaryPayout::with('provider.user:id,name')
            ->where('salon_id', $salonId)
            ->whereDate('salary_month', $month->copy()->startOfMonth()->toDateString())
            ->get()
            ->sortBy(fn (SalaryPayout $p) => $p->provider->user->name ?? '')
            ->map(fn (SalaryPayout $p) => $this->payroll->present($p))
            ->values();

        return response()->json([
            'success' => true,
            'month' => $month->copy()->startOfMonth()->toDateString(),
            'month_label' => $month->format('F Y'),
            'totals' => [
                'staff' => $payslips->count(),
                'base_salary' => round($payslips->sum('base_salary'), 2),
                'commission' => round($payslips->sum('commission_earned'), 2),
                'deductions' => round($payslips->sum('unpaid_leave_deduction'), 2),
                'payable' => round($payslips->sum('total_payable'), 2),
                'paid' => round($payslips->where('status', SalaryPayout::STATUS_PAID)->sum('total_payable'), 2),
            ],
            'payslips' => $payslips,
        ]);
    }

    /**
     * One staff member's payslip, with the service lines behind the commission.
     */
    public function show(Request $request, $salonId, $providerId)
    {
        if ($denied = $this->denyUnlessSelfOrOwner($request, $salonId, $providerId)) {
            return $denied;
        }

        $provider = ServiceProvider::with('user:id,name')
            ->where('salon_id', $salonId)
            ->findOrFail($providerId);

        $month = $this->month($request);
        $payout = $this->payroll->build($provider, $month);

        return response()->json([
            'success' => true,
            'payslip' => $this->payroll->present($payout->load('provider.user:id,name'), withBreakdown: true),
        ]);
    }

    /**
     * The signed-in staff member's own pay, this month and before.
     */
    public function mine(Request $request)
    {
        $provider = ServiceProvider::with('user:id,name')
            ->where('user_id', $request->user()->id)
            ->first();

        if (! $provider) {
            return response()->json(['message' => 'You are not a service provider.'], 403);
        }

        $month = $this->month($request);
        $current = $this->payroll->build($provider, $month);

        // Earlier months are shown as they were recorded, not rebuilt.
        $history = SalaryPayout::where('provider_id', $provider->id)
            ->whereDate('salary_month', '<', $month->copy()->startOfMonth()->toDateString())
            ->orderByDesc('salary_month')
            ->limit(12)
            ->get()
            ->map(fn (SalaryPayout $p) => $this->payroll->present($p->load('provider.user:id,name')))
            ->values();

        return response()->json([
            'success' => true,
            'payslip' => $this->payroll->present($current->load('provider.user:id,name'), withBreakdown: true),
            'history' => $history,
        ]);
    }

    public function recalculate(Request $request, $salonId)
    {
        if ($denied = $this->denyUnlessOwner($request, $salonId)) {
            return $denied;
        }

        $month = $this->month($request);
        $built = $this->payroll->buildForSalon($salonId, $month);

        return response()->json([
            'success' => true,
            'message' => count($built) . ' payslip(s) recalculated for ' . $month->format('F Y') . '.',
        ]);
    }

    public function markPaid(Request $request, $salonId, $payslipId)
    {
        if ($denied = $this->denyUnlessOwner($request, $salonId)) {
            return $denied;
        }

        $validator = Validator::make($request->all(), [
            'payment_reference' => 'nullable|string|max:150',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $payslip = SalaryPayout::where('salon_id', $salonId)->findOrFail($payslipId);

        $payslip = $this->payroll->markPaid(
            $payslip,
            $request->user(),
            $request->input('payment_reference')
        );

        return response()->json([
            'success' => true,
            'message' => 'Salary marked as paid.',
            'payslip' => $this->payroll->present($payslip->load('provider.user:id,name')),
        ]);
    }

    public function markUnpaid(Request $request, $salonId, $payslipId)
    {
        if ($denied = $this->denyUnlessOwner($request, $salonId)) {
            return $denied;
        }

        $payslip = SalaryPayout::where('salon_id', $salonId)->findOrFail($payslipId);
        $payslip = $this->payroll->markUnpaid($payslip);

        return response()->json([
            'success' => true,
            'message' => 'Salary marked as unpaid.',
            'payslip' => $this->payroll->present($payslip->load('provider.user:id,name')),
        ]);
    }

    /**
     * The salon's own copy of what the platform settled, so the commission
     * deducted from each cycle is visible to them and not only to SuperAdmin.
     */
    public function salonPayouts(Request $request, $salonId)
    {
        if ($denied = $this->denyUnlessOwner($request, $salonId)) {
            return $denied;
        }

        $salon = Salon::find($salonId);

        $payouts = SalonPayout::with('salon:id,name')
            ->where('salon_id', $salonId)
            ->orderByDesc('cycle_start_date')
            ->limit(52)
            ->get();

        $model = $salon?->billingModel() ?? \App\Support\BillingModel::SUBSCRIPTION;

        return response()->json([
            'success' => true,
            'billing_model' => $model,
            'billing_label' => \App\Support\BillingModel::label($model),
            'commission_percentage' => $salon?->isOnCommissionModel()
                ? (float) ($salon->commission_percentage ?? 0)
                : null,
            'settlement_rhythm' => \App\Support\PayoutCycle::forBillingModel($model),
            'totals' => [
                'commission_deducted_lifetime' => round((float) $payouts->sum('commission_deducted'), 2),
                'received_lifetime' => round(
                    (float) $payouts->where('status', PayoutService::STATUS_DISTRIBUTED)->sum('net_amount'),
                    2
                ),
            ],
            'payouts' => $payouts->map(fn (SalonPayout $p) => $this->payouts->present($p))->values(),
        ]);
    }

    // ------------------------------------------------------------- internals

    private function month(Request $request): Carbon
    {
        return $request->filled('month')
            ? Carbon::parse($request->month . (strlen($request->month) === 7 ? '-01' : ''))
            : Carbon::today();
    }

    private function denyUnlessOwner(Request $request, string $salonId)
    {
        $user = $request->user();

        if ($user->role === 'superadmin') {
            return null;
        }

        if ($user->role === 'admin'
            && Salon::where('id', $salonId)->where('admin_id', $user->id)->exists()) {
            return null;
        }

        return response()->json(['message' => 'Only the salon owner can see payroll.'], 403);
    }

    /**
     * Staff may read their own payslip; anything wider needs the owner.
     */
    private function denyUnlessSelfOrOwner(Request $request, string $salonId, string $providerId)
    {
        $user = $request->user();

        if ($user->role === 'service_provider') {
            $isSelf = ServiceProvider::where('id', $providerId)
                ->where('user_id', $user->id)
                ->where('salon_id', $salonId)
                ->exists();

            return $isSelf ? null : response()->json(['message' => 'You can only view your own pay.'], 403);
        }

        return $this->denyUnlessOwner($request, $salonId);
    }
}
