<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\SalonPayout;
use App\Services\PayoutService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

/**
 * The weekly payout run.
 *
 * Generate the cycle, check the figures, then distribute. Commission comes off
 * inside the same cycle, before the record is closed, so a salon on the
 * Commission Plan receives the net and the deduction is on the record for both
 * sides to point at afterwards.
 */
class PayoutController extends Controller
{
    public function __construct(private PayoutService $payouts)
    {
    }

    /**
     * A week's payouts, with the totals SuperAdmin needs to sign the run off.
     */
    public function index(Request $request)
    {
        $weekStart = $request->filled('week_start')
            ? Carbon::parse($request->week_start)->startOfWeek()
            : Carbon::today()->startOfWeek();

        $query = SalonPayout::with('salon:id,name')
            ->whereDate('cycle_week_start_date', $weekStart->toDateString());

        if ($request->filled('status')) {
            $query->where('status', $request->status);
        }

        if ($request->filled('billing_type')) {
            $query->where('billing_type', $request->billing_type);
        }

        $payouts = $query->orderBy('created_at')->get();

        return response()->json([
            'success' => true,
            'week_start' => $weekStart->toDateString(),
            'week_end' => $weekStart->copy()->endOfWeek()->toDateString(),
            'totals' => [
                'salons' => $payouts->count(),
                'appointment_revenue' => round((float) $payouts->sum('appointment_revenue'), 2),
                'advances_held' => round((float) $payouts->sum('gross_amount'), 2),
                'commission_deducted' => round((float) $payouts->sum('commission_deducted'), 2),
                'net_to_distribute' => round(
                    (float) $payouts->where('status', '!=', PayoutService::STATUS_DISTRIBUTED)->sum('net_amount'),
                    2
                ),
                'distributed' => round(
                    (float) $payouts->where('status', PayoutService::STATUS_DISTRIBUTED)->sum('net_amount'),
                    2
                ),
            ],
            'payouts' => $payouts->map(fn (SalonPayout $p) => $this->payouts->present($p))->values(),
        ]);
    }

    /**
     * Build (or refresh) every salon's payout for a week.
     */
    public function generate(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'week_start' => 'nullable|date',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $weekStart = $request->filled('week_start')
            ? Carbon::parse($request->week_start)
            : Carbon::today()->subWeek();

        $result = $this->payouts->generateForWeek($weekStart);

        return response()->json([
            'success' => true,
            'message' => "{$result['payouts']} salon payout(s) calculated for the week of {$result['week_start']}.",
        ] + $result);
    }

    public function show($id)
    {
        $payout = SalonPayout::with('salon:id,name,address,phone_num')->findOrFail($id);

        return response()->json([
            'success' => true,
            'payout' => $this->payouts->present($payout),
        ]);
    }

    public function approve(Request $request, $id)
    {
        $payout = SalonPayout::with('salon:id,name')->findOrFail($id);

        try {
            $payout = $this->payouts->approve($payout, $request->user());
        } catch (\RuntimeException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], 422);
        }

        return response()->json([
            'success' => true,
            'message' => 'Payout approved.',
            'payout' => $this->payouts->present($payout->load('salon:id,name')),
        ]);
    }

    /**
     * Hand over the net amount and close the cycle.
     */
    public function distribute(Request $request, $id)
    {
        $validator = Validator::make($request->all(), [
            'distribution_reference' => 'nullable|string|max:150',
            'notes' => 'nullable|string|max:1000',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $payout = SalonPayout::with('salon:id,name')->findOrFail($id);

        try {
            $payout = $this->payouts->markDistributed(
                $payout,
                $request->user(),
                $request->input('distribution_reference'),
                $request->input('notes')
            );
        } catch (\RuntimeException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], 422);
        }

        return response()->json([
            'success' => true,
            'message' => sprintf(
                'Distributed %s to %s after deducting %s commission.',
                number_format((float) $payout->net_amount, 2),
                $payout->salon->name ?? 'the salon',
                number_format((float) $payout->commission_deducted, 2)
            ),
            'payout' => $this->payouts->present($payout->load('salon:id,name')),
        ]);
    }
}
