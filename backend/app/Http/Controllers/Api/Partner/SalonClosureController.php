<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\Salon;
use App\Models\SalonClosure;
use App\Services\SalonClosureService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

/**
 * Emergency day closure and mass reschedule.
 *
 * This wipes a whole day of a salon's bookings, so unlike the other partner
 * endpoints it verifies that the caller actually owns the salon rather than
 * trusting the id in the URL.
 */
class SalonClosureController extends Controller
{
    public function __construct(private SalonClosureService $closures)
    {
    }

    /**
     * Closures from today onwards, with how many bookings each one released.
     */
    public function index(Request $request, $salonId)
    {
        if ($denied = $this->denyUnlessOwner($request, $salonId)) {
            return $denied;
        }

        $closures = SalonClosure::withCount([
                'appointments as released_count',
                'appointments as awaiting_reschedule_count' => fn ($q) => $q->where('status', 'awaiting_reschedule'),
            ])
            ->active()
            ->where('salon_id', $salonId)
            ->whereDate('closed_date', '>=', Carbon::today())
            ->orderBy('closed_date')
            ->get();

        return response()->json(['closures' => $closures]);
    }

    /**
     * What closing a date would do. The admin sees this before confirming —
     * cancelling a day of trade is not something to discover after the fact.
     */
    public function preview(Request $request, $salonId)
    {
        if ($denied = $this->denyUnlessOwner($request, $salonId)) {
            return $denied;
        }

        $validator = Validator::make($request->all(), [
            'date' => 'required|date|after_or_equal:today',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $date = Carbon::parse($request->date)->format('Y-m-d');

        return response()->json($this->closures->preview($salonId, $date));
    }

    /**
     * Close the day: block new bookings and release the existing ones for a
     * free reschedule, notifying every affected customer.
     */
    public function store(Request $request, $salonId)
    {
        if ($denied = $this->denyUnlessOwner($request, $salonId)) {
            return $denied;
        }

        $validator = Validator::make($request->all(), [
            'date' => 'required|date|after_or_equal:today',
            'reason' => 'nullable|string|max:255',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $date = Carbon::parse($request->date)->format('Y-m-d');

        $result = $this->closures->closeDay(
            $salonId,
            $date,
            $request->input('reason'),
            $request->user()->id
        );

        return response()->json([
            'message' => $result['released'] === 0
                ? 'The day is closed. There were no bookings to move.'
                : "{$result['released']} booking(s) released for a free reschedule.",
            'closure' => $result['closure'],
            'released_count' => $result['released'],
            'notified_count' => $result['notified'],
            'untouchable_count' => $result['untouchable_count'],
            'advance_carried_forward' => $result['advance_carried_forward'],
        ], 201);
    }

    /**
     * Re-open a day. Bookings already released stay released — their customers
     * have been told, and reinstating them silently would double-book the day.
     */
    public function destroy(Request $request, $salonId, $closureId)
    {
        if ($denied = $this->denyUnlessOwner($request, $salonId)) {
            return $denied;
        }

        $closure = SalonClosure::where('salon_id', $salonId)->findOrFail($closureId);
        $stillWaiting = $this->closures->reopenDay($closure, $request->user()->id);

        return response()->json([
            'message' => $stillWaiting > 0
                ? "The day is open for new bookings again. {$stillWaiting} released booking(s) were not restored — "
                    . 'those customers were already told and must pick their own new slot.'
                : 'The day is open for new bookings again.',
            'still_awaiting_reschedule' => $stillWaiting,
        ]);
    }

    /**
     * Only the salon's own admin (or a superadmin) may close its day.
     */
    private function denyUnlessOwner(Request $request, string $salonId)
    {
        $user = $request->user();

        if ($user->role === 'superadmin') {
            return null;
        }

        $isOwner = Salon::where('id', $salonId)->where('admin_id', $user->id)->exists();

        if ($user->role === 'admin' && $isOwner) {
            return null;
        }

        return response()->json(
            ['message' => 'Only the salon owner can change its opening days.'],
            403
        );
    }
}
