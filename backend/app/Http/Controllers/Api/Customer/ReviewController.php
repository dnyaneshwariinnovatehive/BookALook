<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use App\Models\Complaint;
use App\Models\Notification;
use App\Models\Salon;
use App\Services\ReviewService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * What the customer says about a visit afterwards.
 *
 * Two different things arrive through the same door, on purpose. A rating is
 * public and routine — the salon lives with it and other customers read it. A
 * complaint is private, goes straight to SuperAdmin, and can end with the salon
 * warned or taken offline. Asking for both in one place means a customer never
 * has to hunt for a way to escalate, and never has to escalate just to be heard.
 */
class ReviewController extends Controller
{
    public function __construct(private ReviewService $reviews)
    {
    }

    /**
     * Visits this customer still owes a review for.
     *
     * The app asks this on opening and, if anything comes back, puts up the
     * rating sheet. Returning the whole list rather than just a count lets the
     * sheet be drawn without a second round trip — the customer is already
     * waiting on the home screen.
     */
    public function pending(Request $request)
    {
        $pending = $this->reviews->awaitingReview($request->user()->id);

        return response()->json([
            'success' => true,
            'data' => $pending->map(fn (Appointment $appointment) => [
                'appointment_id' => $appointment->id,
                'salon_id' => $appointment->salon_id,
                'salon_name' => $appointment->salon->name ?? 'Salon',
                'salon_cover_url' => $appointment->salon->cover_photo_url,
                'provider_name' => $appointment->appointedProvider->user->name ?? null,
                'appointment_date' => $appointment->appointment_date,
                'visited_label' => $this->reviews->ageLabel($appointment->created_at),
            ])->values(),
        ]);
    }

    /**
     * Rate a visit, and optionally report it.
     *
     * The rating is required and the words are not: a star takes a second and a
     * paragraph takes a minute, and a system that demands the paragraph gets
     * neither. Both halves are written in one transaction so a customer can
     * never end up having complained about a visit the platform has no record of
     * them rating.
     */
    public function store(Request $request, string $appointmentId)
    {
        $data = $request->validate([
            'rating' => 'required|integer|min:1|max:5',
            'comment' => 'nullable|string|max:2000',

            // Escalation. Only read when the customer asked for it.
            'raise_complaint' => 'boolean',
            'complaint_subject' => 'required_if:raise_complaint,true|nullable|string|max:150',
            'complaint_description' => 'required_if:raise_complaint,true|nullable|string|max:2000',
        ]);

        $appointment = Appointment::where('customer_id', $request->user()->id)
            ->find($appointmentId);

        if (! $appointment) {
            return response()->json(['success' => false, 'message' => 'Booking not found.'], 404);
        }

        $can = $this->reviews->reviewability($appointment);

        if (! $can['allowed']) {
            return response()->json(['success' => false, 'message' => $can['reason']], 422);
        }

        $wantsComplaint = $request->boolean('raise_complaint');

        $result = DB::transaction(function () use ($appointment, $data, $wantsComplaint, $request) {
            $review = $this->reviews->record(
                $appointment,
                (int) $data['rating'],
                $data['comment'] ?? null
            );

            $complaint = $wantsComplaint
                ? $this->raiseComplaint($appointment, $data, $request)
                : null;

            return [$review, $complaint];
        });

        [$review, $complaint] = $result;

        return response()->json([
            'success' => true,
            'message' => $complaint
                ? 'Thanks — your rating is live and your report has gone to the BookALook team.'
                : 'Thanks for rating your visit.',
            'review' => [
                'id' => $review->id,
                'rating' => $review->rating,
                'comment' => $review->comment,
            ],
            'complaint_id' => $complaint?->id,
        ], 201);
    }

    /**
     * Send a report to SuperAdmin and make sure somebody is actually told.
     *
     * A complaint that only lands in a table is a complaint nobody reads, so
     * every SuperAdmin gets it in their inbox at the same moment.
     */
    private function raiseComplaint(Appointment $appointment, array $data, Request $request): Complaint
    {
        $complaint = Complaint::create([
            'salon_id' => $appointment->salon_id,
            'customer_id' => $appointment->customer_id,
            'related_appointment_id' => $appointment->id,
            'subject' => $data['complaint_subject'],
            'description' => $data['complaint_description'],
            'status' => Complaint::STATUS_OPEN,
        ]);

        $salonName = Salon::where('id', $appointment->salon_id)->value('name') ?? 'a salon';

        foreach (\App\Models\User::where('role', 'superadmin')->pluck('id') as $superAdminId) {
            Notification::create([
                'user_id' => $superAdminId,
                'type' => 'complaint_raised',
                'title' => "Complaint about {$salonName}",
                'message' => $complaint->subject,
                'data' => [
                    'action' => 'review_complaint',
                    'complaint_id' => $complaint->id,
                    'salon_id' => $appointment->salon_id,
                ],
                'related_salon_id' => $appointment->salon_id,
                'is_read' => false,
            ]);
        }

        return $complaint;
    }

    /**
     * The public review list for a salon — the "see all reviews" page.
     *
     * Filterable by star and by whether there are words to read, because the
     * two questions a reader actually has are "what do the one-star reviews
     * say" and "show me the ones that said something".
     */
    public function forSalon(Request $request, string $salonId)
    {
        $request->validate([
            'page' => 'nullable|integer|min:1',
            'rating' => 'nullable|integer|min:1|max:5',
            'with_comment' => 'nullable|boolean',
        ]);

        if (! Salon::where('id', $salonId)->exists()) {
            return response()->json(['success' => false, 'message' => 'Salon not found.'], 404);
        }

        $list = $this->reviews->listFor(
            $salonId,
            (int) $request->input('page', 1),
            20,
            $request->filled('rating') ? (int) $request->rating : null,
            $request->boolean('with_comment')
        );

        return response()->json([
            'success' => true,
            'summary' => $this->reviews->summaryFor($salonId),
        ] + $list);
    }
}
