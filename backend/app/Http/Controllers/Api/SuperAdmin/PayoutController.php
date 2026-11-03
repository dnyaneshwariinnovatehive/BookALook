<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\SalonPayout;
use App\Services\AuditLogger;
use App\Services\PayoutService;
use App\Support\BillingModel;
use App\Support\PayoutCycle;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
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
    /** Orderings the UI may request for the payout table. */
    private const SORTABLE = [
        'created_at', 'status', 'salon',
        'appointments_count', 'appointment_revenue', 'gross_amount',
        'commission_deducted', 'net_amount',
    ];

    public function __construct(private PayoutService $payouts)
    {
    }

    /**
     * One cycle's payouts, with the totals SuperAdmin needs to sign the run off.
     */
    public function index(Request $request)
    {
        $request->validate(self::FILTER_RULES + [
            'per_page' => 'nullable|integer|min:5|max:100',
            'column' => 'nullable|in:' . implode(',', self::SORTABLE),
            'direction' => 'nullable|in:asc,desc',
        ]);

        $cycleType = $this->cycleType($request);
        [$start, $end] = PayoutCycle::bounds($cycleType, $this->anchor($request));

        // Filters shared by the totals roll-up, the page of rows and the CSV
        // export, so they always describe the same set.
        $applyFilters = fn ($query) => $this->filtered($query, $request, $cycleType, $start);

        $column = $request->input('column');
        $direction = $request->input('direction') === 'asc' ? 'asc' : 'desc';

        // settlementInvoice is eager-loaded because present() hands back its
        // signed link, and a page of 20 payouts would otherwise be 20 queries.
        $rowQuery = $applyFilters(SalonPayout::with(['salon:id,name', 'settlementInvoice', 'paymentSubmissions']));

        if ($column === 'salon') {
            $rowQuery->orderBy(
                DB::table('salons')->select('name')->whereColumn('salons.id', 'salon_payouts.salon_id')->limit(1),
                $direction
            );
        } elseif ($column && in_array($column, self::SORTABLE, true)) {
            $rowQuery->orderBy($column, $direction);
        } else {
            $rowQuery->orderBy('created_at');
        }
        $rowQuery->orderBy('id');

        // Totals are rolled up in SQL, so signing off a cycle never depends on
        // which page of rows happens to be on screen.
        $totals = $applyFilters(SalonPayout::query())
            ->selectRaw('count(*) as salons')
            ->selectRaw('coalesce(sum(appointment_revenue), 0) as appointment_revenue')
            ->selectRaw('coalesce(sum(gross_amount), 0) as advances_held')
            ->selectRaw('coalesce(sum(commission_deducted), 0) as commission_deducted')
            ->selectRaw('coalesce(sum(case when status <> ? then net_amount else 0 end), 0) as net_to_distribute', [PayoutService::STATUS_DISTRIBUTED])
            ->selectRaw('coalesce(sum(case when status = ? then net_amount else 0 end), 0) as distributed', [PayoutService::STATUS_DISTRIBUTED])
            ->first();

        $perPage = (int) $request->input('per_page', 20);
        $paged = $rowQuery->paginate($perPage);

        return response()->json([
            'success' => true,
            'cycle_type' => $cycleType,
            'cycle_label' => PayoutCycle::label($cycleType, $start, $end),
            'cycle_start' => $start->toDateString(),
            'cycle_end' => $end->toDateString(),
            // Still running: figures are a preview and cannot be approved yet.
            'cycle_in_progress' => $end->copy()->startOfDay()->gte(Carbon::today()),
            // The cycle is rebuilt by app:generate-payouts every day at 04:00
            // and by the Recalculate button; this is when that last happened.
            'last_calculated_at' => optional(
                SalonPayout::where('cycle_type', $cycleType)
                    ->whereDate('cycle_start_date', $start->toDateString())
                    ->max('updated_at'),
                fn ($t) => Carbon::parse($t)->toIso8601String()
            ),
            'totals' => [
                'salons' => (int) $totals->salons,
                'appointment_revenue' => round((float) $totals->appointment_revenue, 2),
                'advances_held' => round((float) $totals->advances_held, 2),
                'commission_deducted' => round((float) $totals->commission_deducted, 2),
                'net_to_distribute' => round((float) $totals->net_to_distribute, 2),
                'distributed' => round((float) $totals->distributed, 2),
            ],
            'payouts' => $paged->getCollection()->map(fn (SalonPayout $p) => $this->payouts->present($p))->values(),
            'meta' => [
                'current_page' => $paged->currentPage(),
                'last_page' => $paged->lastPage(),
                'per_page' => $paged->perPage(),
                'total' => $paged->total(),
            ],
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
        $payout = SalonPayout::with(['salon', 'settlementInvoice', 'paymentSubmissions'])->findOrFail($id);

        // Every line this payout settles: the bookings (with who and when) and
        // any late refunds, so SuperAdmin can answer "why this amount?".
        $items = DB::table('salon_payout_items as i')
            ->leftJoin('appointments as a', 'a.id', '=', 'i.appointment_id')
            ->leftJoin('users as u', 'u.id', '=', 'a.customer_id')
            ->where('i.salon_payout_id', $payout->id)
            ->orderBy('a.appointment_date')
            ->orderBy('a.start_time')
            ->get([
                'i.id', 'i.kind', 'i.appointment_id', 'i.appointment_status', 'i.gross_amount',
                'i.commission_base', 'i.commission_rate', 'i.commission_amount', 'i.refund_amount', 'i.net_amount',
                'a.appointment_date', 'a.start_time', 'a.booking_source',
                DB::raw('COALESCE(u.name, a.walk_in_customer_name) as customer_name'),
            ])
            ->map(fn ($r) => [
                'id' => $r->id,
                'kind' => $r->kind ?? 'booking',
                'appointment_id' => $r->appointment_id,
                'date' => $r->appointment_date ? Carbon::parse($r->appointment_date)->toDateString() : null,
                'time' => $r->start_time ? substr((string) $r->start_time, 0, 5) : null,
                'customer_name' => $r->customer_name,
                'source' => $r->booking_source,
                'appointment_status' => $r->appointment_status,
                'advance_held' => round((float) $r->gross_amount, 2),
                'commission_base' => round((float) $r->commission_base, 2),
                'commission_rate' => round((float) $r->commission_rate, 2),
                'commission' => round((float) $r->commission_amount, 2),
                'refund' => round((float) $r->refund_amount, 2),
                'net' => round((float) $r->net_amount, 2),
            ])->values();

        // Who approved, paid or collected it, and when — from the audit log.
        $history = AuditLog::with('actor:id,name')
            ->where('entity_type', 'SalonPayout')
            ->where('entity_id', $payout->id)
            ->orderBy('created_at')
            ->get()
            ->map(fn (AuditLog $log) => [
                'action' => $log->action,
                'label' => AuditLog::CATALOGUE[$log->action]['label'] ?? $log->action,
                'by' => $log->actor?->name,
                'at' => $log->created_at?->toIso8601String(),
                'reference' => $log->metadata['distribution_reference'] ?? null,
                'note' => $log->metadata['reason'] ?? null,
            ])->values();

        return response()->json([
            'success' => true,
            'payout' => $this->payouts->present($payout),
            'items' => $items,
            // Masked: the full account number is only shown through the
            // salon bank-details endpoint, which logs the reveal.
            'bank_details' => $payout->salon ? app(\App\Services\BankDetailsService::class)->present($payout->salon) : null,
            'payment_submissions' => $payout->paymentSubmissions->sortByDesc('created_at')->map->present()->values(),
            'history' => $history,
        ]);
    }

    /**
     * Everything waiting on SuperAdmin, across every cycle, oldest first:
     * payouts to approve, approved payouts to pay, salon payments to verify,
     * and money salons owe that has not come in.
     */
    public function inbox()
    {
        $today = Carbon::today();
        $open = fn () => SalonPayout::with(['salon:id,name', 'settlementInvoice', 'paymentSubmissions'])
            ->where('status', '!=', PayoutService::STATUS_DISTRIBUTED);
        $row = function (SalonPayout $p, ?string $since) use ($today) {
            return $this->payouts->present($p) + [
                'waiting_since' => $since,
                'waiting_days' => $since ? (int) Carbon::parse($since)->startOfDay()->diffInDays($today) : null,
            ];
        };

        $toApprove = $open()->where('status', PayoutService::STATUS_PENDING)
            ->whereDate('cycle_end_date', '<', $today)
            ->orderBy('cycle_end_date')->limit(200)->get()
            ->map(fn ($p) => $row($p, Carbon::parse($p->cycle_end_date)->addDay()->toDateString()));

        $toPay = $open()->where('status', PayoutService::STATUS_APPROVED)
            ->where('net_amount', '>=', 0)
            ->orderBy('approved_at')->limit(200)->get()
            ->map(fn ($p) => $row($p, $p->approved_at ? Carbon::parse($p->approved_at)->toDateString() : null));

        $toVerify = $open()->whereHas('paymentSubmissions', fn ($q) => $q->where('status', 'pending'))
            ->limit(200)->get()
            ->map(function ($p) use ($row) {
                $sub = $p->paymentSubmissions->where('status', 'pending')->sortBy('created_at')->first();

                return $row($p, $sub?->created_at?->toDateString());
            })
            ->sortByDesc('waiting_days')->values();

        $owed = $open()->where('net_amount', '<', 0)
            ->whereDate('cycle_end_date', '<', $today)
            ->whereDoesntHave('paymentSubmissions', fn ($q) => $q->where('status', 'pending'))
            ->orderBy('cycle_end_date')->limit(200)->get()
            ->map(fn ($p) => $row($p, Carbon::parse($p->cycle_end_date)->addDay()->toDateString()));

        return response()->json([
            'success' => true,
            'counts' => [
                'to_approve' => $toApprove->count(),
                'to_pay' => $toPay->count(),
                'to_verify' => $toVerify->count(),
                'salons_owe' => $owed->count(),
            ],
            'to_approve' => $toApprove->values(),
            'to_pay' => $toPay->values(),
            'to_verify' => $toVerify,
            'salons_owe' => $owed->values(),
        ]);
    }

    /** Both settlement rhythms at a glance: what is owed each way, and this month. */
    public function overview()
    {
        $today = Carbon::today();
        $monthStart = $today->copy()->startOfMonth();
        $monthEnd = $today->copy()->endOfMonth();
        $openEnded = fn () => SalonPayout::where('status', '!=', PayoutService::STATUS_DISTRIBUTED)
            ->whereDate('cycle_end_date', '<', $today);
        $paidThisMonth = fn () => SalonPayout::where('status', PayoutService::STATUS_DISTRIBUTED)
            ->whereBetween('distributed_at', [$monthStart, $monthEnd->copy()->endOfDay()]);

        return response()->json([
            'success' => true,
            'month_label' => $today->format('F Y'),
            'to_pay_salons' => round((float) $openEnded()->where('net_amount', '>', 0)->sum('net_amount'), 2),
            'to_pay_count' => $openEnded()->where('net_amount', '>', 0)->count(),
            'salons_owe' => round(abs((float) $openEnded()->where('net_amount', '<', 0)->sum('net_amount')), 2),
            'salons_owe_count' => $openEnded()->where('net_amount', '<', 0)->count(),
            'paid_this_month' => round((float) $paidThisMonth()->where('net_amount', '>', 0)->sum('net_amount'), 2),
            'collected_this_month' => round(abs((float) $paidThisMonth()->where('net_amount', '<', 0)->sum('net_amount')), 2),
            // Commission on cycles that started this month, both rhythms.
            'commission_this_month' => round((float) SalonPayout::whereBetween('cycle_start_date', [$monthStart->toDateString(), $monthEnd->toDateString()])
                ->sum('commission_deducted'), 2),
        ]);
    }

    /** The selected cycle (with the page's filters) as a CSV, for the accountant. */
    public function export(Request $request)
    {
        $request->validate(self::FILTER_RULES);

        $cycleType = $this->cycleType($request);
        [$start, $end] = PayoutCycle::bounds($cycleType, $this->anchor($request));

        $rows = $this->filtered(SalonPayout::with(['salon:id,name', 'settlementInvoice']), $request, $cycleType, $start)
            ->orderBy(DB::table('salons')->select('name')->whereColumn('salons.id', 'salon_payouts.salon_id')->limit(1))
            ->get();

        $filename = sprintf('bookalook-payouts-%s-%s.csv', $cycleType, $start->toDateString());

        return response()->streamDownload(function () use ($rows) {
            $out = fopen('php://output', 'w');
            fwrite($out, "\xEF\xBB\xBF"); // UTF-8 BOM so Excel shows ₹ and names correctly
            fputcsv($out, [
                'Salon', 'Billing', 'Cycle', 'Cycle start', 'Cycle end', 'Appointments', 'Billed (app bookings)',
                'Advances held', 'Commission %', 'Commission', 'Refunds deducted', 'Coins added', 'Dues adjustment',
                'Net', 'Direction', 'Status', 'Approved at', 'Paid / collected at', 'Reference', 'Statement no.',
            ]);
            foreach ($rows as $p) {
                $d = $this->payouts->present($p);
                fputcsv($out, [
                    self::csvSafe($d['salon_name']), $d['billing_label'], $d['cycle_label'], $d['cycle_start_date'], $d['cycle_end_date'],
                    $d['appointments_count'], $d['appointment_revenue'], $d['gross_amount'], $d['commission_percentage'],
                    $d['commission_deducted'], $d['refund_adjustment'], $d['wallet_redeemed_amount'], $d['dues_adjustment'],
                    $d['net_amount'], $d['direction'] === 'salon_owes' ? 'Salon owes' : 'Pay salon', ucfirst($d['status']),
                    $d['approved_at'] ? Carbon::parse($d['approved_at'])->toDateTimeString() : '',
                    $d['distributed_at'] ? Carbon::parse($d['distributed_at'])->toDateTimeString() : '',
                    self::csvSafe($d['distribution_reference']), $d['settlement_invoice']['number'] ?? '',
                ]);
            }
            fclose($out);
        }, $filename, ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    /** Filters the list, totals and export share. */
    private const FILTER_RULES = [
        'search' => 'nullable|string|max:100',
        'flow' => 'nullable|in:pay_salon,salon_owes',
        'has_refunds' => 'nullable|boolean',
        'payment' => 'nullable|in:pending,rejected',
        'status' => 'nullable|in:pending,approved,distributed',
    ];

    private function filtered($query, Request $request, string $cycleType, Carbon $start)
    {
        $query->where('cycle_type', $cycleType)
            ->whereDate('cycle_start_date', $start->toDateString());

        if ($request->filled('status')) {
            $query->where('status', $request->status);
        }

        if ($request->filled('billing_type')) {
            $query->where('billing_type', BillingModel::normalise($request->billing_type));
        }

        if ($request->filled('search')) {
            $term = '%' . mb_strtolower(trim((string) $request->search)) . '%';
            $query->whereHas('salon', fn ($q) => $q->whereRaw('LOWER(name) LIKE ?', [$term]));
        }

        match ($request->input('flow')) {
            'salon_owes' => $query->where('net_amount', '<', 0),
            'pay_salon' => $query->where('net_amount', '>=', 0),
            default => null,
        };

        if ($request->boolean('has_refunds')) {
            $query->where('refund_adjustment', '>', 0);
        }

        if ($request->input('payment') === 'pending') {
            $query->whereHas('paymentSubmissions', fn ($q) => $q->where('status', 'pending'));
        } elseif ($request->input('payment') === 'rejected') {
            $query->whereHas('paymentSubmissions', fn ($q) => $q->where('status', 'rejected'))
                ->whereDoesntHave('paymentSubmissions', fn ($q) => $q->whereIn('status', ['pending', 'approved']));
        }

        return $query;
    }

    /** A cell starting with = + - @ would run as a formula in Excel. */
    private static function csvSafe(?string $value): string
    {
        $value = (string) $value;

        return $value !== '' && in_array($value[0], ['=', '+', '-', '@'], true) ? "'" . $value : $value;
    }

    public function approve(Request $request, $id)
    {
        $payout = SalonPayout::with('salon:id,name')->findOrFail($id);

        try {
            $payout = $this->payouts->approve($payout, $request->user());
        } catch (\RuntimeException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], 422);
        }

        AuditLogger::record(
            action: AuditLog::PAYOUT_APPROVED,
            entity: $payout,
            label: sprintf('%s payout', $payout->salon->name ?? 'Salon'),
            after: ['status' => $payout->status, 'net_amount' => (float) $payout->net_amount],
            metadata: ['payout_id' => $payout->id],
        );

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

        // A salon that owes pays offline, so recording it as collected needs
        // the payment's reference — it is the only trace of money received.
        if ((float) $payout->net_amount < 0 && ! $request->filled('distribution_reference')) {
            return response()->json([
                'success' => false,
                'message' => 'This salon owes BookALook. Enter the UPI or bank reference of the payment you received.',
                'errors' => ['distribution_reference' => ['Enter the reference of the payment received.']],
            ], 422);
        }

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

        $this->tellSalonSettled($payout, $request->input('distribution_reference'));

        // Money actually leaving the platform. Nothing else in the system is
        // less reversible.
        AuditLogger::record(
            action: AuditLog::PAYOUT_DISTRIBUTED,
            entity: $payout,
            label: sprintf('%s payout', $payout->salon->name ?? 'Salon'),
            after: [
                'status' => $payout->status,
                'net_amount' => (float) $payout->net_amount,
                'commission_deducted' => (float) $payout->commission_deducted,
            ],
            metadata: [
                'reason' => $request->input('notes'),
                'payout_id' => $payout->id,
                'distribution_reference' => $request->input('distribution_reference'),
            ],
        );

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

    /**
     * The salon's screenshot shows the full amount it owed: settle the payout.
     * For a Commission Model month that renews the salon's access.
     */
    public function approvePayment(Request $request, $id, $submissionId)
    {
        $submission = \App\Models\PayoutPaymentSubmission::where('id', $submissionId)
            ->where('salon_payout_id', $id)
            ->firstOrFail();

        try {
            $payout = app(\App\Services\PayoutDuesService::class)->approve($submission, $request->user());
        } catch (\RuntimeException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], 422);
        }

        AuditLogger::record(
            action: AuditLog::PAYOUT_DISTRIBUTED,
            entity: $payout,
            label: sprintf('%s paid what it owed', $payout->salon->name ?? 'Salon'),
            after: ['status' => $payout->status, 'amount_received' => (float) $submission->amount],
            metadata: ['payout_id' => $payout->id, 'payment_submission_id' => $submission->id],
        );

        return response()->json([
            'success' => true,
            'message' => 'Payment verified and the payout marked paid.',
            'payout' => $this->payouts->present($payout->load('salon:id,name')),
        ]);
    }

    /**
     * The screenshot does not prove the full payment. The salon sees the
     * reason and pays again; what it owes is unchanged.
     */
    public function rejectPayment(Request $request, $id, $submissionId)
    {
        $request->validate(['reason' => 'required|string|min:3|max:500']);

        $submission = \App\Models\PayoutPaymentSubmission::where('id', $submissionId)
            ->where('salon_payout_id', $id)
            ->firstOrFail();

        try {
            $submission = app(\App\Services\PayoutDuesService::class)->reject($submission, $request->user(), $request->input('reason'));
        } catch (\RuntimeException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], 422);
        }

        return response()->json([
            'success' => true,
            'message' => 'Payment declined. The salon has been told why.',
            'payout' => $this->payouts->present($submission->payout->load('salon:id,name')),
        ]);
    }

    /**
     * All payouts for a specific salon across cycles.
     */
    public function forSalon($salonId)
    {
        $salon = \App\Models\Salon::findOrFail($salonId);

        $payouts = SalonPayout::with(['salon:id,name', 'settlementInvoice'])
            ->where('salon_id', $salonId)
            ->orderByDesc('cycle_start_date')
            ->limit(52)
            ->get();

        $model = $salon->billingModel();

        return response()->json([
            'success' => true,
            'salon' => ['id' => $salon->id, 'name' => $salon->name],
            'billing_model' => $model,
            'billing_label' => BillingModel::label($model),
            'commission_percentage' => $salon->isOnCommissionModel()
                ? (float) ($salon->commission_percentage ?? 0)
                : null,
            'settlement_rhythm' => PayoutCycle::forBillingModel($model),
            'totals' => [
                'commission_deducted_lifetime' => round((float) $payouts->sum('commission_deducted'), 2),
                'advances_held_lifetime' => round((float) $payouts->sum('gross_amount'), 2),
                'appointment_revenue_lifetime' => round((float) $payouts->sum('appointment_revenue'), 2),
                'received_lifetime' => round(
                    (float) $payouts->where('status', PayoutService::STATUS_DISTRIBUTED)->sum('net_amount'),
                    2
                ),
                'pending_lifetime' => round(
                    (float) $payouts->where('status', '!=', PayoutService::STATUS_DISTRIBUTED)->sum('net_amount'),
                    2
                ),
                'count' => $payouts->count(),
            ],
            'payouts' => $payouts->map(fn (SalonPayout $p) => $this->payouts->present($p))->values(),
        ]);
    }

    // ------------------------------------------------------------- internals

    /**
     * Tell the salon owner the money moved (push + in-app), so they are not
     * left asking "did you pay us?". The settlement stands whether or not the
     * notice goes out.
     */
    private function tellSalonSettled(SalonPayout $payout, ?string $reference): void
    {
        try {
            $payout->loadMissing('salon');
            $label = PayoutCycle::label(
                $payout->cycle_type ?? PayoutCycle::WEEKLY,
                Carbon::parse($payout->cycle_start_date),
                Carbon::parse($payout->cycle_end_date)
            );
            $amount = '₹' . number_format(abs((float) $payout->net_amount), 2);
            $ref = $reference ? " Ref {$reference}." : '';
            $owes = (float) $payout->net_amount < 0;

            app(\App\Services\Notifications\NotificationService::class)->send(
                $payout->salon?->admin_id,
                \App\Support\Notifications\NotificationType::GENERAL,
                $owes ? 'Payment received' : 'Payout sent',
                $owes
                    ? "We have received your payment of {$amount} for {$label}.{$ref} Thank you!"
                    : "{$amount} for {$label} has been sent to your account.{$ref} Your statement is in Payouts.",
                ['payout_id' => $payout->id, 'action' => 'open_payouts'],
                salon: $payout->salon,
                dedupeKey: 'payout.settled.' . $payout->id,
            );
        } catch (\Throwable $e) {
            report($e);
        }
    }

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
