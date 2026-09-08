<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\SalonPayout;
use App\Services\PayoutService;
use App\Support\BillingModel;
use App\Support\PayoutCycle;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

/**
 * The payout run.
 *
 * Generate the cycle, check the figures, then distribute. Two rhythms share
 * this screen because they settle the same way:
 *
 *  - Weekly, for salons on a Subscription Plan. They have already paid for
 *    access, so the run only hands back the advances the platform is holding.
 *  - Monthly on the 1st, for salons on the Commission Model. Commission is
 *    deducted inside the cycle, before the record is closed, so the salon
 *    receives the net and the deduction stays on the record for both sides to
 *    point at afterwards. Settling a month also buys the salon the next one.
 */
class PayoutController extends Controller
{
    public function __construct(private PayoutService $payouts)
    {
    }

    /**
     * One cycle's payouts, with the totals SuperAdmin needs to sign the run off.
     */
    public function index(Request $request)
    {
        $cycleType = $this->cycleType($request);
        [$start, $end] = PayoutCycle::bounds($cycleType, $this->anchor($request));

        $query = SalonPayout::with('salon:id,name')
            ->where('cycle_type', $cycleType)
            ->whereDate('cycle_start_date', $start->toDateString());

        if ($request->filled('status')) {
            $query->where('status', $request->status);
        }

        if ($request->filled('billing_type')) {
            $query->where('billing_type', BillingModel::normalise($request->billing_type));
        }

        $payouts = $query->orderBy('created_at')->get();

        return response()->json([
            'success' => true,
            'cycle_type' => $cycleType,
            'cycle_label' => PayoutCycle::label($cycleType, $start, $end),
            'cycle_start' => $start->toDateString(),
            'cycle_end' => $end->toDateString(),
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
     * Build (or refresh) every salon's payout for a cycle.
     *
     * With no cycle named, both legs run for whatever has just closed — which
     * is what the scheduled job does.
     */
    public function generate(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'cycle_type' => 'nullable|in:' . implode(',', PayoutCycle::ALL),
            'cycle_start' => 'nullable|date',
            // Kept so an older client calling with week_start still works.
            'week_start' => 'nullable|date',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        if (! $request->filled('cycle_type')) {
            $result = $this->payouts->generateDue(force: true);

            return response()->json([
                'success' => true,
                'message' => sprintf(
                    '%d weekly payout(s) for %s and %d monthly payout(s) for %s.',
                    $result['weekly']['payouts'],
                    $result['weekly']['start'],
                    $result['monthly']['payouts'] ?? 0,
                    $result['monthly']['start'] ?? '—'
                ),
                'weekly' => $result['weekly'],
                'monthly' => $result['monthly'],
            ]);
        }

        $cycleType = $request->cycle_type;
        $anchor = $this->anchor($request, defaultToPrevious: true);

        $result = $cycleType === PayoutCycle::MONTHLY
            ? $this->payouts->generateMonthly($anchor)
            : $this->payouts->generateWeekly($anchor);

        return response()->json([
            'success' => true,
            'message' => sprintf(
                '%d salon payout(s) calculated for the %s cycle starting %s.',
                $result['payouts'],
                $cycleType,
                $result['start']
            ),
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

        $isCommission = BillingModel::isCommission($payout->billing_type);

        return response()->json([
            'success' => true,
            'message' => $isCommission
                ? sprintf(
                    'Distributed %s to %s after deducting %s commission. Their access now runs to %s.',
                    number_format((float) $payout->net_amount, 2),
                    $payout->salon->name ?? 'the salon',
                    number_format((float) $payout->commission_deducted, 2),
                    optional($payout->salon?->currentSubscription)->end_date?->format('j M Y') ?? 'the next cycle'
                )
                : sprintf(
                    'Distributed %s in held advances to %s.',
                    number_format((float) $payout->net_amount, 2),
                    $payout->salon->name ?? 'the salon'
                ),
            'payout' => $this->payouts->present($payout->load('salon:id,name')),
        ]);
    }

    // ------------------------------------------------------------- internals

    private function cycleType(Request $request): string
    {
        $requested = $request->input('cycle_type');

        return in_array($requested, PayoutCycle::ALL, true) ? $requested : PayoutCycle::WEEKLY;
    }

    /**
     * The date the caller is asking about. `week_start` is still honoured so an
     * older client keeps working.
     */
    private function anchor(Request $request, bool $defaultToPrevious = false): Carbon
    {
        $given = $request->input('cycle_start') ?? $request->input('week_start');

        if ($given) {
            return Carbon::parse($given);
        }

        if (! $defaultToPrevious) {
            return Carbon::today();
        }

        return $this->cycleType($request) === PayoutCycle::MONTHLY
            ? Carbon::today()->subMonthNoOverflow()
            : Carbon::today()->subWeek();
    }
}
