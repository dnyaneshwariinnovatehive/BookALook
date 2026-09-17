<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\ServiceProvider;
use App\Models\SalaryPayout;
use App\Models\ProviderLeave;
use App\Services\PayrollService;
use Carbon\Carbon;
use Illuminate\Http\Request;

class SuperAdminStaffController extends Controller
{
    public function __construct(
        private PayrollService $payroll,
    ) {}

    public function show(Request $request, $salonId, $providerId)
    {
        $provider = ServiceProvider::with([
            'user:id,name,phone,email,is_active', 
            'services.template:id,name,category_id', 
            'services.template.category:id,name',
            'workingHours'
        ])
        ->where('salon_id', $salonId)
        ->findOrFail($providerId);

        $month = Carbon::today();
        
        // Ensure current month payroll is built to include latest appointments
        $currentPayroll = $this->payroll->build($provider, $month);

        // Fetch payroll history (last 12 months)
        $history = SalaryPayout::where('provider_id', $providerId)
            ->whereDate('salary_month', '<', $month->copy()->startOfMonth()->toDateString())
            ->orderByDesc('salary_month')
            ->limit(12)
            ->get()
            ->map(fn (SalaryPayout $p) => $this->payroll->present($p->load('provider.user:id,name')))
            ->values();

        // Fetch leaves
        $leaves = ProviderLeave::where('provider_id', $providerId)
            ->orderByDesc('leave_date')
            ->limit(30)
            ->get();

        return response()->json([
            'success' => true,
            'provider' => $provider,
            'payroll' => [
                'current' => $this->payroll->present($currentPayroll->load('provider.user:id,name'), withBreakdown: true),
                'history' => $history,
            ],
            'leaves' => $leaves,
        ]);
    }
}
