<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\PayoutPaymentSubmission;
use App\Models\Salon;
use App\Models\SalonPayout;
use App\Models\SalonSupportRequest;
use App\Services\PayoutService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Where a salon stands with BookALook, and a way to write to it.
 *
 * Outside the plan gate on purpose: the lock screen is exactly where an owner
 * needs to see what is still owed either way, and to ask about it.
 * Owner only — staff see "Call the owner" instead.
 */
class SalonSupportController extends Controller
{
    /** Settlements not yet closed, split by which way the money goes. */
    public function settlementSummary(Request $request, string $salonId)
    {
        if ($denied = $this->denyUnlessOwner($request, $salonId)) {
            return $denied;
        }

        $open = SalonPayout::with('paymentSubmissions')
            ->where('salon_id', $salonId)
            ->whereIn('status', [PayoutService::STATUS_PENDING, PayoutService::STATUS_APPROVED])
            ->where('net_amount', '!=', 0)
            ->orderBy('cycle_start_date')
            ->get()
            // A cycle still running is a preview, not something owed yet.
            ->reject(fn (SalonPayout $p) => PayoutService::cycleInProgress($p))
            ->values();

        $owedToSalon = $open->filter(fn ($p) => (float) $p->net_amount > 0);
        $owedBySalon = $open->filter(fn ($p) => (float) $p->net_amount < 0);
        $underReview = $owedBySalon->filter(fn ($p) => $p->paymentSubmissions
            ->contains('status', PayoutPaymentSubmission::STATUS_PENDING));

        return response()->json([
            'success' => true,
            'pending_count' => $open->count(),
            'owed_to_salon' => [
                'amount' => round((float) $owedToSalon->sum('net_amount'), 2),
                'count' => $owedToSalon->count(),
            ],
            'owed_by_salon' => [
                'amount' => round(abs((float) $owedBySalon->sum('net_amount')), 2),
                'count' => $owedBySalon->count(),
                'under_review' => $underReview->count(),
            ],
            'settlements' => $open->map(fn (SalonPayout $p) => [
                'id' => $p->id,
                'label' => Carbon::parse($p->cycle_start_date)->format('j M') . ' – ' . Carbon::parse($p->cycle_end_date)->format('j M Y'),
                'direction' => (float) $p->net_amount < 0 ? 'salon_owes' : 'pay_salon',
                'amount' => round(abs((float) $p->net_amount), 2),
                'status' => $p->status,
            ])->all(),
            'open_requests' => SalonSupportRequest::where('salon_id', $salonId)
                ->where('status', SalonSupportRequest::STATUS_OPEN)
                ->count(),
        ]);
    }

    public function index(Request $request, string $salonId)
    {
        if ($denied = $this->denyUnlessOwner($request, $salonId)) {
            return $denied;
        }

        $requests = SalonSupportRequest::with('payout')
            ->where('salon_id', $salonId)
            ->latest()
            ->limit(50)
            ->get();

        return response()->json([
            'success' => true,
            'topics' => collect(SalonSupportRequest::TOPICS)->map(fn ($label, $key) => ['key' => $key, 'label' => $label])->values(),
            'requests' => $requests->map->present()->values(),
        ]);
    }

    public function store(Request $request, string $salonId)
    {
        if ($denied = $this->denyUnlessOwner($request, $salonId)) {
            return $denied;
        }

        $data = $request->validate([
            'topic' => ['required', Rule::in(array_keys(SalonSupportRequest::TOPICS))],
            'message' => 'required|string|min:5|max:2000',
            // Only one of this salon's own settlements.
            'salon_payout_id' => [
                'nullable',
                Rule::exists('salon_payouts', 'id')->where('salon_id', $salonId),
            ],
        ]);

        $supportRequest = SalonSupportRequest::create([
            'salon_id' => $salonId,
            'user_id' => $request->user()->id,
            'topic' => $data['topic'],
            'message' => trim($data['message']),
            'salon_payout_id' => $data['salon_payout_id'] ?? null,
            'status' => SalonSupportRequest::STATUS_OPEN,
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Sent to BookALook. You will get a notification when they reply.',
            'request' => $supportRequest->load('payout')->present(),
        ], 201);
    }

    private function denyUnlessOwner(Request $request, string $salonId)
    {
        $user = $request->user();

        if ($user->role === 'admin'
            && Salon::where('id', $salonId)->where('admin_id', $user->id)->exists()) {
            return null;
        }

        return response()->json(['message' => 'Only the salon owner can see this.'], 403);
    }
}
