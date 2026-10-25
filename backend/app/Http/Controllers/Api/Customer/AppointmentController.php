<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use App\Models\AppointmentService;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\Invoice;
use App\Models\PlatformPolicySetting;
use App\Models\ServiceProvider;
use App\Models\Salon;
use App\Services\AvailabilityService;
use App\Services\BookingPaymentService;
use App\Services\BookingPolicyService;
use App\Services\InvoiceService;
use App\Services\Notifications\NotificationService;
use App\Services\Payments\PaymentGatewayException;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;
use Carbon\Carbon;

class AppointmentController extends Controller
{
    public function __construct(
        private AvailabilityService $availability,
        private BookingPolicyService $policy,
        private BookingPaymentService $payments,
        private NotificationService $notifications,
        private InvoiceService $invoices,
    ) {
    }

    /**
     * Staff of the salon, flagged against the services currently in the cart.
     * Providers who cannot perform every service are returned with
     * is_eligible = false so the app can grey them out.
     */
    public function getProviders(Request $request, $salon_id)
    {
        $date = $request->query('date');
        $cart = $this->activeCart($request, $salon_id);
        $requirements = $cart
            ? $this->availability->summariseCart($cart)
            : ['service_ids' => [], 'duration' => AvailabilityService::SLOT_MINUTES, 'total' => 0, 'advance' => 0];

        $closure = $this->availability->salonClosureStatus($salon_id, $date);

        $providers = $this->availability->providersForSalon(
            $salon_id,
            $requirements['service_ids'],
            $date,
            $requirements['duration']
        );

        $noProvidersReason = null;
        if ($closure['closed']) {
            $noProvidersReason = $closure['reason'];
        } elseif (empty($providers)) {
            $noProvidersReason = 'No service provider is available for the selected date or time.';
        }

        return response()->json([
            'salon_closed' => $closure['closed'],
            'closed_reason' => $closure['reason'],
            'no_providers_reason' => $noProvidersReason,
            'providers' => $providers,
            'total_duration_minutes' => $requirements['duration'],
            'total_amount' => $requirements['total'],
            'advance_amount' => $requirements['advance'],
        ]);
    }

    /**
     * 30-minute slot grid for a date and provider. Every block is returned —
     * unavailable ones carry `available: false` plus a reason so the app can
     * grey them out rather than hide them.
     */
    public function getAvailableSlots(Request $request, $salon_id)
    {
        $validator = Validator::make($request->all(), [
            'date' => 'required|date|after_or_equal:today',
            'provider_id' => 'nullable|exists:service_providers,id' // required; enforced in candidateProviders()
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $cart = $this->activeCart($request, $salon_id);

        if (!$cart || $cart->items->isEmpty()) {
            return response()->json(['message' => 'Cart is empty.'], 400);
        }

        $requirements = $this->availability->summariseCart($cart);
        $candidates = $this->candidateProviders($salon_id, $requirements['service_ids'], $request->provider_id);

        if ($candidates instanceof \Illuminate\Http\JsonResponse) {
            return $candidates;
        }

        $result = $this->availability->generateSlots(
            $salon_id,
            $request->date,
            $candidates,
            $requirements['duration']
        );

        // Too many same-day cancellations/reschedules means advance-only no
        // longer applies for that date.
        $requirement = $this->policy->paymentRequirement($request->user()->id, $request->date);
        $payableNow = $requirement['full_upfront'] ? $requirements['total'] : $requirements['advance'];

        return response()->json([
            'date' => $request->date,
            'provider_id' => $request->provider_id,
            'total_duration_minutes' => $requirements['duration'],
            'total_amount' => $requirements['total'],
            'advance_amount' => $payableNow,
            'full_upfront_required' => $requirement['full_upfront'],
            'same_day_changes_used' => $requirement['changes_used'],
            'same_day_change_threshold' => $requirement['threshold'],
            'closed' => $result['closed'],
            'closed_reason' => $result['reason'],
            'has_available_slots' => $result['has_available_slots'] ?? false,
            'unavailable_reason' => $result['unavailable_reason'] ?? null,
            'slots' => $result['slots'],
        ]);
    }

    /**
     * Reserve the slot and open a payment for it.
     *
     * The booking is created as `pending_payment` and holds the chair while the
     * customer is on the payment sheet, so nobody else can take the same time
     * mid-checkout. It only becomes a real appointment once the payment is
     * verified; an abandoned checkout gives the slot back when the hold expires.
     *
     * The cart is deliberately left alone until the payment lands — a customer
     * whose payment fails should find their basket where they left it.
     */
    public function book(Request $request, $salon_id)
    {
        $validator = Validator::make($request->all(), [
            'date' => 'required|date|after_or_equal:today',
            'time' => 'required|date_format:H:i',
            'provider_id' => 'nullable|exists:service_providers,id' // required; enforced in candidateProviders()
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $user = $request->user();
        $cart = $this->activeCart($request, $salon_id);

        if (!$cart || $cart->items->isEmpty()) {
            return response()->json(['message' => 'Cart is empty.'], 400);
        }

        // Validate that all items in the cart remain active and bookable.
        // If any catalog items were retired, gracefully remove them, preserve valid items, and explain the issue.
        $retiredItemNames = [];
        foreach ($cart->items as $item) {
            $isRetired = false;
            $name = null;
            if ($item->service_id) {
                $service = $item->service;
                if (! $service || ! $service->is_active || $service->trashed() || ! $service->template || ! $service->template->is_active || $service->template->trashed()) {
                    $isRetired = true;
                    $name = $service?->template?->name ?? 'A service';
                }
            } elseif ($item->combo_id) {
                $combo = $item->combo;
                if (! $combo || ! $combo->is_active) {
                    $isRetired = true;
                    $name = $combo?->name ?? 'A combo package';
                }
            }

            if ($isRetired) {
                $retiredItemNames[] = $name;
                $item->delete();
            }
        }

        if (! empty($retiredItemNames)) {
            $uniqueNames = array_values(array_unique($retiredItemNames));
            $namesStr = implode(', ', $uniqueNames);
            $message = count($uniqueNames) === 1
                ? "The offering '{$namesStr}' is no longer available and has been removed from your cart. Please review your updated cart before booking."
                : "The following offerings are no longer available and have been removed from your cart: {$namesStr}. Please review your updated cart before booking.";

            return response()->json([
                'message' => $message,
                'retired_items_removed' => true,
                'removed_offerings' => $uniqueNames,
            ], 422);
        }

        $requirements = $this->availability->summariseCart($cart);
        $candidates = $this->candidateProviders(
            $salon_id,
            $requirements['service_ids'],
            $request->provider_id,
            $request->date,
            $requirements['duration']
        );

        if ($candidates instanceof \Illuminate\Http\JsonResponse) {
            return $candidates;
        }

        // A previous attempt the customer abandoned is still sitting on a slot.
        // Give it back before taking another one, so tapping Book twice cannot
        // silently hold two chairs.
        $this->releaseAbandonedAttempts($user->id, $salon_id);

        DB::beginTransaction();
        try {
            // Re-check the slot inside the transaction so a slot taken while the
            // customer was choosing cannot be double-booked.
            $appointedProviderId = $this->availability->resolveProviderForSlot(
                $salon_id,
                $request->date,
                $request->time,
                $candidates,
                $requirements['duration']
            );

            if (!$appointedProviderId) {
                DB::rollBack();
                return response()->json([
                    'message' => 'That slot is no longer available. Please pick another time.',
                    'slot_unavailable' => true,
                ], 409);
            }

            $endTime = Carbon::parse($request->date . ' ' . $request->time)
                ->addMinutes($requirements['duration'])
                ->format('H:i:s');

            // Past the same-day change threshold the customer loses advance-only
            // and must pay the whole amount upfront for that date.
            $requirement = $this->policy->paymentRequirement($user->id, $request->date);
            $payableNow = $requirement['full_upfront'] ? $requirements['total'] : $requirements['advance'];

            $appointment = new Appointment([
                'salon_id' => $salon_id,
                'customer_id' => $user->id,
                'appointed_provider_id' => $appointedProviderId,
                'booking_source' => 'online',
                'appointment_date' => $request->date,
                'start_time' => $request->time . ':00',
                'end_time' => $endTime,
                // Held, not booked. The slot is blocked but the customer owns
                // nothing until the money is verified.
                'status' => 'pending_payment',
                'payment_hold_expires_at' => now()->addMinutes($this->payments->holdMinutes()),
                'payment_option' => $requirement['full_upfront'] ? 'full_upfront' : 'advance_only',
                'total_amount' => $requirements['total'],
                'advance_amount' => $payableNow,
                'balance_amount' => $requirements['total'] - $payableNow,
            ]);
            $appointment->save();

            // Snapshot every line at the price actually charged. A combo the
            // customer assembled service by service is recorded as that combo,
            // so the appointment agrees with the cart they were shown and the
            // salon can see which package was sold.
            $priced = app(\App\Services\CartPricingService::class)->price($cart);
            $servicesById = $cart->items->filter(fn ($i) => $i->service)
                ->mapWithKeys(fn ($i) => [$i->service_id => $i->service]);

            // Handle first-time customer offer reservation inside the transaction
            $ftd = $priced['first_time_discount'] ?? null;
            $phoneHash = \App\Models\FirstTimeOffer::hashPhone($user->phone);

            if ($ftd && ! empty($ftd['applied']) && ! empty($ftd['offer_id'])) {
                $offer = \App\Models\FirstTimeOffer::where('id', $ftd['offer_id'])->lockForUpdate()->first();
                $eligibilityService = app(\App\Services\CustomerOfferEligibilityService::class);

                if (! $offer || ! $offer->is_active || ! $offer->isCurrentlyValid()) {
                    DB::rollBack();
                    return response()->json([
                        'message' => 'The promotional offer has expired or is no longer active.',
                        'offer_invalid' => true,
                    ], 422);
                }

                if ($eligibilityService->isCampaignLimitReached($offer, true)) {
                    DB::rollBack();
                    return response()->json([
                        'message' => 'This promotional offer has reached its maximum redemption capacity.',
                        'offer_limit_reached' => true,
                    ], 409);
                }

                if ($eligibilityService->hasQualifyingBooking($user, $offer->scope, $salon_id)) {
                    DB::rollBack();
                    return response()->json([
                        'message' => 'You are not eligible for this first-time customer offer.',
                        'ineligible_offer' => true,
                    ], 422);
                }

                if ($eligibilityService->hasCommittedRedemption($user, $offer->id)) {
                    DB::rollBack();
                    return response()->json([
                        'message' => 'This first-time offer has already been redeemed.',
                        'already_redeemed' => true,
                    ], 422);
                }

                if ($eligibilityService->hasActiveReservation($user, $offer->id)) {
                    DB::rollBack();
                    return response()->json([
                        'message' => 'An active reservation for this offer is already in progress.',
                        'conflict' => 'active_reservation_in_progress',
                    ], 409);
                }

                $entitlementKey = $offer->makeEntitlementKey($user, $salon_id);

                $appointment->forceFill([
                    'first_time_offer_id' => $offer->id,
                    'first_time_discount_amount' => (float) $ftd['total_discount'],
                    'customer_phone_hash' => $phoneHash,
                ])->save();

                try {
                    \App\Models\FirstTimeOfferRedemption::create([
                        'offer_id' => $offer->id,
                        'customer_id' => $user->id,
                        'customer_phone_hash' => $phoneHash,
                        'salon_id' => $salon_id,
                        'appointment_id' => $appointment->id,
                        'status' => \App\Models\FirstTimeOfferRedemption::STATUS_RESERVED,
                        'active_entitlement_key' => $entitlementKey,
                        'scope' => $offer->scope,
                        'discount_amount' => (float) $ftd['total_discount'],
                        'reserved_at' => now(),
                    ]);
                } catch (\Illuminate\Database\QueryException $e) {
                    DB::rollBack();

                    $isUniqueViolation = $e->getCode() === '23505'
                        || ($e->getCode() === '23000' && str_contains(strtolower($e->getMessage()), 'unique'))
                        || str_contains(strtolower($e->getMessage()), 'duplicate');

                    if ($isUniqueViolation) {
                        return response()->json([
                            'message' => 'An active booking attempt is already in progress for this offer.',
                            'conflict' => true,
                        ], 409);
                    }

                    throw $e;
                }
            } elseif ($phoneHash) {
                $appointment->forceFill(['customer_phone_hash' => $phoneHash])->save();
            }

            foreach ($priced['applied_combos'] as $match) {
                for ($i = 0; $i < $match['applications']; $i++) {
                    foreach ($match['services'] as $line) {
                        $service = $servicesById[$line['service_id']] ?? null;

                        if ($service) {
                            $this->createAppointmentService(
                                $appointment->id,
                                $service,
                                (float) $line['combo_price'],
                                $match['combo_id']
                            );
                        }
                    }
                }
            }

            foreach ($priced['loose_services'] as $line) {
                $service = $servicesById[$line['service_id']] ?? null;

                if (! $service) {
                    continue;
                }

                $lineDiscount = 0.0;
                if ($ftd && ! empty($ftd['lines'][$line['service_id']])) {
                    $lineDiscount = (float) $ftd['lines'][$line['service_id']]['line_discount'];
                }

                $qty = max(1, (int) $line['quantity']);
                $unitDiscount = $qty > 0 ? round($lineDiscount / $qty, 2) : 0.0;

                for ($i = 0; $i < $qty; $i++) {
                    $this->createAppointmentService(
                        $appointment->id,
                        $service,
                        (float) $line['price'],
                        null,
                        $unitDiscount
                    );
                }
            }

            // Packages the customer picked deliberately.
            foreach ($cart->items as $item) {
                if (! $item->combo) {
                    continue;
                }

                for ($i = 0; $i < max(1, (int) $item->quantity); $i++) {
                    foreach ($item->combo->services as $service) {
                        $this->createAppointmentService(
                            $appointment->id,
                            $service,
                            (float) ($service->pivot->combo_special_price ?? $service->price),
                            $item->combo_id
                        );
                    }
                }
            }

            DB::commit();
        } catch (\Exception $e) {
            DB::rollBack();
            return response()->json(['message' => 'Failed to book appointment.', 'error' => $e->getMessage()], 500);
        }

        // Nothing to collect (an all-free basket, or a policy that asks for no
        // advance) — there is no point sending the customer to a payment sheet.
        if ($payableNow <= 0) {
            $this->settleBooking($appointment, $cart);

            return response()->json([
                'message' => 'Appointment booked successfully.',
                'payment_required' => false,
                'payment' => null,
                'appointment' => $appointment->load('services.service.template', 'appointedProvider.user'),
            ]);
        }

        // The slot is held but the money has not moved. Saying so is the only
        // sign the customer gets that the booking exists at all, and without it
        // the app has to be reopened to find out.
        $this->notifications->bookingAwaitingPayment(
            $appointment,
            $appointment->salon?->name ?? 'the salon',
            (float) $payableNow,
        );

        // The gateway call is deliberately outside the transaction: it is a
        // network round trip, and a slow provider must not hold a write lock.
        try {
            ['order' => $order] = $this->payments->openOrder($appointment, (float) $payableNow);
        } catch (PaymentGatewayException $e) {
            report($e);
            $this->payments->release($appointment, 'Could not start the payment.');

            return response()->json([
                'message' => 'We could not start the payment. Please try again.',
            ], 502);
        }

        return response()->json([
            'message' => 'Slot held. Complete the payment to confirm your booking.',
            'payment_required' => true,
            'payment' => $this->payments->checkoutPayload($appointment, $order, (float) $payableNow),
            'appointment' => $appointment->load('services.service.template', 'appointedProvider.user'),
        ], 201);
    }

    /**
     * Confirm a payment the gateway told the app succeeded.
     *
     * The signature is what makes this safe to expose: the app is telling us it
     * paid, and only the provider (or, in demo, this server) can produce a
     * signature that agrees.
     */
    public function confirmPayment(Request $request, $id)
    {
        $validator = Validator::make($request->all(), [
            'razorpay_payment_id' => 'required|string|max:150',
            'razorpay_signature' => 'required|string|max:500',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $appointment = Appointment::where('customer_id', $request->user()->id)->findOrFail($id);

        return $this->settlePayment(
            $request,
            $appointment,
            $request->razorpay_payment_id,
            $request->razorpay_signature
        );
    }

    /**
     * Complete a payment on the demo gateway.
     *
     * Exists so the whole order → pay → verify → confirm path can be exercised
     * without live keys. It refuses outright once a real gateway is configured,
     * so it can never become a way to book without paying.
     */
    public function demoPay(Request $request, $id)
    {
        $appointment = Appointment::where('customer_id', $request->user()->id)->findOrFail($id);

        $simulated = $this->payments->simulatePayment($appointment);

        if (! $simulated) {
            return response()->json([
                'message' => 'Demo payments are not available.',
            ], 400);
        }

        return $this->settlePayment(
            $request,
            $appointment,
            $simulated['payment_id'],
            $simulated['signature']
        );
    }

    /**
     * Give up on a held slot straight away rather than waiting for the hold to
     * lapse, so the chair goes back on sale the moment the customer backs out.
     */
    public function abandonPayment(Request $request, $id)
    {
        $appointment = Appointment::where('customer_id', $request->user()->id)->findOrFail($id);

        if ($appointment->status !== 'pending_payment') {
            return response()->json(['message' => 'This booking is not awaiting payment.'], 400);
        }

        $this->payments->release($appointment, 'Payment was cancelled by the customer.');

        return response()->json(['message' => 'Booking cancelled. Your slot has been released.']);
    }

    /**
     * Shared tail of both confirm paths: verify, then turn the hold into a
     * real booking.
     */
    private function settlePayment(Request $request, Appointment $appointment, string $paymentId, string $signature)
    {
        if ($appointment->status === 'scheduled') {
            // A retried confirmation — the first one already booked it.
            return response()->json([
                'message' => 'This booking is already confirmed.',
                'appointment' => $this->presentBooking($appointment->load($this->bookingRelations())),
            ]);
        }

        // Delegate payment verification, race reconciliation, and atomic settlement to BookingPaymentService
        $result = $this->payments->confirm($appointment, $paymentId, $signature, $request->user()->id);

        if (! $result['ok']) {
            if (! empty($result['hold_expired'])) {
                return response()->json([
                    'message' => $result['message'],
                    'hold_expired' => true,
                    'refunded' => $result['refunded'] ?? false,
                    'refund_pending' => $result['refund_pending'] ?? false,
                    'already_refunded' => $result['already_refunded'] ?? false,
                ], 409);
            }

            return response()->json(['message' => $result['message']], 422);
        }

        $freshAppointment = $appointment->fresh();

        $this->settleBooking($freshAppointment, $this->activeCart($request, $freshAppointment->salon_id));

        return response()->json([
            'message' => 'Payment received. Your appointment is confirmed.',
            'appointment' => $this->presentBooking($freshAppointment->load($this->bookingRelations())),
        ]);
    }

    /**
     * Turn a paid hold into a confirmed booking and retire the cart behind it.
     *
     * The single place a booking becomes real, and therefore the single place the
     * "you are booked" notices come from. Both confirm paths — a free booking and
     * a paid one — land here, so there is no way for one of them to confirm
     * silently.
     */
    private function settleBooking(Appointment $appointment, ?Cart $cart): void
    {
        DB::transaction(function () use ($appointment, $cart) {
            $appointment->forceFill([
                'status' => 'scheduled',
                'payment_hold_expires_at' => null,
            ])->save();

            // If the appointment has an active reservation, commit it
            $redemption = \App\Models\FirstTimeOfferRedemption::where('appointment_id', $appointment->id)
                ->where('status', \App\Models\FirstTimeOfferRedemption::STATUS_RESERVED)
                ->first();

            if ($redemption) {
                $redemption->commit();
            }

            if ($cart) {
                $cart->items()->delete();
                $cart->status = 'converted';
                $cart->save();
            }
        });

        $salonName = $appointment->salon?->name ?? 'the salon';
        $dateLabel = $this->dateTimeLabel($appointment);

        // The salon side of the same event. The provider is told the slot is
        // theirs; the owner is told the salon has a booking, because otherwise
        // they find out by opening the app.
        $this->notifications->notifySalonOfNewBooking($appointment, $salonName, $dateLabel);

        // Notify the customer that the booking is confirmed.
        // Invoices are generated only when the appointment is completed.
        $this->notifications->bookingConfirmed($appointment, $salonName, $dateLabel);
    }

    /**
     * Drop any slot this customer is still holding at this salon from an
     * earlier, unfinished checkout.
     */
    private function releaseAbandonedAttempts(string $customerId, string $salonId): void
    {
        Appointment::where('customer_id', $customerId)
            ->where('salon_id', $salonId)
            ->where('status', 'pending_payment')
            ->get()
            ->each(fn (Appointment $a) => $this->payments->release($a, 'Replaced by a newer booking attempt.'));
    }

    /**
     * The customer's active cart for this salon, with everything the
     * availability engine needs eager-loaded.
     */
    private function activeCart(Request $request, $salon_id): ?Cart
    {
        return Cart::with(['items.service.template', 'items.combo.services.template'])
            ->where('customer_id', $request->user()->id)
            ->where('salon_id', $salon_id)
            ->where('status', 'active')
            ->first();
    }

    /**
     * Resolve the requested provider into the candidate list the availability
     * engine works with, or a JSON error when the choice is invalid.
     *
     * A provider is mandatory. There used to be an "Any Available" option, but
     * the booked provider is the person who scans the customer's QR at the
     * salon, so a booking has to name someone the customer actually chose.
     * Rejected here rather than in each validator so the customer gets a
     * readable message instead of a bare validation bag.
     *
     * @return string[]|\Illuminate\Http\JsonResponse
     */
    private function candidateProviders(
        string $salonId,
        array $serviceIds,
        ?string $providerId,
        ?string $date = null,
        int $durationMinutes = AvailabilityService::SLOT_MINUTES
    ) {
        if ($providerId === null || $providerId === '') {
            return response()->json([
                'message' => 'Please choose a service provider for this booking.',
            ], 422);
        }

        $providers = $this->availability->providersForSalon($salonId, $serviceIds);

        $chosen = collect($providers)->firstWhere('id', $providerId);

        if (!$chosen) {
            return response()->json(['message' => 'That service provider does not work at this salon.'], 422);
        }

        if (!$chosen['is_eligible']) {
            $missing = implode(', ', $chosen['missing_service_names']);
            return response()->json([
                'message' => "{$chosen['name']} does not perform: {$missing}.",
            ], 422);
        }

        if ($date !== null) {
            $availableOnDate = $this->availability->providersForSalon($salonId, $serviceIds, $date, $durationMinutes);
            $stillAvailable = collect($availableOnDate)->firstWhere('id', $providerId);
            if (!$stillAvailable) {
                return response()->json([
                    'message' => "{$chosen['name']} is not available on this date.",
                ], 422);
            }
        }

        return [$providerId];
    }

    private function createAppointmentService(
        string $appointmentId,
        $service,
        float $price,
        ?string $comboId = null,
        float $firstTimeDiscount = 0.0
    ): void {
        AppointmentService::create([
            'appointment_id' => $appointmentId,
            'service_id' => $service->id,
            'combo_id' => $comboId,
            'price_at_booking' => $price,
            'original_service_price' => $service->price,
            'first_time_discount_amount' => $firstTimeDiscount,
            'duration_minutes_at_booking' => $service->template->estimated_duration_minutes ?? AvailabilityService::SLOT_MINUTES,
            'line_status' => 'booked',
        ]);
    }

    /**
     * Get Customer's upcoming and past appointments, each decorated with what
     * the customer is allowed to do with it right now.
     */
    public function index(Request $request)
    {
        $appointments = Appointment::with($this->bookingRelations())
            ->where('customer_id', $request->user()->id)
            // A slot held for an unfinished payment is not a booking yet, and
            // listing it would tell the customer they have an appointment they
            // have not actually paid for.
            ->where('status', '!=', 'pending_payment')
            // Abandoned unpaid holds that were released by the system without ever being confirmed
            // must not be listed as cancelled appointments in the customer's history.
            // An appointment only shows as cancelled if it was a real booking cancelled by the customer
            // (e.g. by pressing cancel button), salon admin, or had an actual successful payment record.
            ->where(function ($q) {
                $q->where('status', '!=', 'cancelled')
                    ->orWhere('cancelled_by', '!=', 'system')
                    ->orWhereExists(function ($sub) {
                        $sub->select(DB::raw(1))
                            ->from('payments')
                            ->whereColumn('payments.appointment_id', 'appointments.id')
                            ->where('payments.status', 'success');
                    });
            })
            ->orderBy('appointment_date', 'desc')
            ->orderBy('start_time', 'desc')
            ->get();

        $upcoming = [];
        $past = [];

        foreach ($appointments as $appointment) {
            $payload = $this->presentBooking($appointment);

            if ($this->policy->isUpcoming($appointment)) {
                $upcoming[] = $payload;
            } else {
                $past[] = $payload;
            }
        }

        // Upcoming reads best soonest-first; history reads best newest-first.
        $upcoming = array_reverse($upcoming);

        // Sort so that items needing reschedule appear at the top
        usort($upcoming, function ($a, $b) {
            $aNeeds = $a['needs_reschedule'] ?? false;
            $bNeeds = $b['needs_reschedule'] ?? false;
            
            if ($aNeeds && !$bNeeds) return -1;
            if (!$aNeeds && $bNeeds) return 1;
            
            // If both need it or neither need it, keep chronological order
            return strcmp($a['appointment_date'] . ' ' . $a['start_time'], $b['appointment_date'] . ' ' . $b['start_time']);
        });

        // Bookings the salon released. Surfaced separately so the home tab can
        // raise an alert without downloading and filtering the whole list.
        $actionRequired = array_values(array_filter(
            $upcoming,
            fn ($booking) => $booking['needs_reschedule'] === true
        ));

        return response()->json([
            'upcoming' => $upcoming,
            'past' => $past,
            'action_required' => $actionRequired,
            'cancellation_cutoff_minutes' => $this->policy->cancellationCutoffMinutes(),
            'reschedule_cutoff_minutes' => $this->policy->rescheduleCutoffMinutes(),
        ]);
    }

    /**
     * A single booking with all of its detail.
     */
    public function show(Request $request, $id)
    {
        $appointment = Appointment::with($this->bookingRelations())
            ->where('customer_id', $request->user()->id)
            ->findOrFail($id);

        return response()->json(['appointment' => $this->presentBooking($appointment)]);
    }

    /**
     * Cancel an appointment, subject to the SuperAdmin cutoff. The advance is
     * refunded only for services whose own refund setting allows it.
     */
    public function cancel(Request $request, $id)
    {
        $appointment = Appointment::with($this->bookingRelations())
            ->where('customer_id', $request->user()->id)
            ->findOrFail($id);

        $window = $this->policy->cancellationWindow($appointment);

        if (! $window['allowed']) {
            return response()->json(['message' => $window['reason']], 422);
        }

        $refund = $this->policy->refundBreakdown($appointment);

        $pendingRefundIds = [];

        DB::beginTransaction();
        try {
            $releasedBySalon = $this->policy->wasReleasedBySalon($appointment);

            $appointment->status = 'cancelled';
            $appointment->cancelled_by = 'customer';
            $appointment->cancelled_by_user_id = $request->user()->id;
            $appointment->cancellation_reason = $request->input('reason');
            $appointment->cancelled_at = now();
            $appointment->save();

            $appointment->services()->update(['line_status' => 'cancelled']);

            // Any invoice associated with a cancelled booking is removed.
            Invoice::where('appointment_id', $appointment->id)->delete();

            $pendingRefundIds = $this->createPendingRefundRecords(
                $appointment,
                $refund['refundable'],
                $releasedBySalon
                    ? 'Salon closed the day — full advance returned'
                    : 'Customer cancellation',
                $request->user()->id
            );

            DB::commit();
        } catch (\Exception $e) {
            DB::rollBack();
            return response()->json(['message' => 'Failed to cancel appointment.', 'error' => $e->getMessage()], 500);
        }

        // Post-commit: Execute gateway refunds outside the open database transaction
        foreach ($pendingRefundIds as $refundId) {
            $this->payments->processPendingRefund($refundId);
        }

        $date = Carbon::parse($appointment->appointment_date)->format('Y-m-d');

        // After the commit, so the notification describes a booking that exists.
        // The customer gets the cancellation in their inbox; the provider whose
        // slot just freed up is told separately, because they are the one who
        // will want to sell that time again.
        $this->notifications->bookingCancelled(
            $appointment,
            $appointment->salon?->name ?? 'the salon',
            $this->dateTimeLabel($appointment),
        );

        return response()->json([
            'message' => 'Appointment cancelled successfully.',
            'refund' => $refund,
            'payment_requirement' => $this->policy->paymentRequirement($request->user()->id, $date),
            'appointment' => $this->presentBooking($appointment->fresh($this->bookingRelations())),
        ]);
    }

    /**
     * Providers and slots for moving an existing booking. Same engine as
     * checkout, but the basket comes from the appointment's own service lines
     * and the appointment's current slot does not block itself.
     */
    public function rescheduleOptions(Request $request, $id)
    {
        $validator = Validator::make($request->all(), [
            'date' => 'nullable|date|after_or_equal:today',
            'provider_id' => 'nullable|exists:service_providers,id',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $appointment = Appointment::with($this->bookingRelations())
            ->where('customer_id', $request->user()->id)
            ->findOrFail($id);

        $window = $this->policy->rescheduleWindow($appointment);

        if (! $window['allowed']) {
            return response()->json(['message' => $window['reason']], 422);
        }

        $requirements = $this->availability->summariseAppointment($appointment);
        $providers = $this->availability->providersForSalon($appointment->salon_id, $requirements['service_ids']);

        $response = [
            'providers' => $providers,
            'current_provider_id' => $appointment->appointed_provider_id,
            'current_date' => Carbon::parse($appointment->appointment_date)->format('Y-m-d'),
            'current_time' => substr($appointment->start_time, 0, 5),
            'total_duration_minutes' => $requirements['duration'],
            'total_amount' => $requirements['total'],
            'advance_amount' => $requirements['advance'],
            'free_reschedule' => $window['free_reschedule'],
        ];

        if (! $request->filled('date')) {
            return response()->json($response);
        }

        $candidates = $this->candidateProviders(
            $appointment->salon_id,
            $requirements['service_ids'],
            $request->provider_id
        );

        if ($candidates instanceof \Illuminate\Http\JsonResponse) {
            return $candidates;
        }

        $slots = $this->availability->generateSlots(
            $appointment->salon_id,
            $request->date,
            $candidates,
            $requirements['duration'],
            $appointment->id
        );

        return response()->json($response + [
            'date' => $request->date,
            'closed' => $slots['closed'],
            'closed_reason' => $slots['reason'],
            'slots' => $slots['slots'],
        ]);
    }

    /**
     * Move a booking to a new slot. The original row is kept (status
     * 'rescheduled') so its financial history survives; a new appointment is
     * created pointing back at it via rescheduled_from_id, and any paid amount
     * is carried forward through payment_allocations rather than refunded.
     */
    public function reschedule(Request $request, $id)
    {
        $validator = Validator::make($request->all(), [
            'date' => 'required|date|after_or_equal:today',
            'time' => 'required|date_format:H:i',
            'provider_id' => 'nullable|exists:service_providers,id',
            'reason' => 'nullable|string|max:255',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $appointment = Appointment::with($this->bookingRelations())
            ->where('customer_id', $request->user()->id)
            ->findOrFail($id);

        $window = $this->policy->rescheduleWindow($appointment);

        if (! $window['allowed']) {
            return response()->json(['message' => $window['reason']], 422);
        }

        $requirements = $this->availability->summariseAppointment($appointment);
        $candidates = $this->candidateProviders(
            $appointment->salon_id,
            $requirements['service_ids'],
            $request->provider_id,
            $request->date,
            $requirements['duration']
        );

        if ($candidates instanceof \Illuminate\Http\JsonResponse) {
            return $candidates;
        }

        DB::beginTransaction();
        try {
            $providerId = $this->availability->resolveProviderForSlot(
                $appointment->salon_id,
                $request->date,
                $request->time,
                $candidates,
                $requirements['duration'],
                $appointment->id
            );

            if (! $providerId) {
                DB::rollBack();
                return response()->json([
                    'message' => 'That slot is no longer available. Please pick another time.',
                    'slot_unavailable' => true,
                ], 409);
            }

            $endTime = Carbon::parse($request->date . ' ' . $request->time)
                ->addMinutes($requirements['duration'])
                ->format('H:i:s');

            $replacement = Appointment::create([
                'salon_id' => $appointment->salon_id,
                'customer_id' => $appointment->customer_id,
                'appointed_provider_id' => $providerId,
                'booking_source' => $appointment->booking_source,
                'appointment_date' => $request->date,
                'start_time' => $request->time . ':00',
                'end_time' => $endTime,
                'status' => 'scheduled',
                'payment_option' => $appointment->payment_option,
                'total_amount' => $appointment->total_amount,
                'advance_amount' => $appointment->advance_amount,
                'balance_amount' => $appointment->balance_amount,
                'rescheduled_from_id' => $appointment->id,
                'reschedule_reason' => $request->input(
                    'reason',
                    $window['free_reschedule'] ? 'Salon closed on the original date' : null
                ),
            ]);

            // Copy the snapshotted service lines onto the new appointment.
            foreach ($appointment->services->where('line_status', '!=', 'cancelled') as $line) {
                $copy = $line->replicate(['id', 'appointment_id', 'created_at', 'updated_at']);
                $copy->appointment_id = $replacement->id;
                $copy->serving_provider_id = null; // set again at QR scan time
                $copy->line_status = 'booked';
                $copy->save();
            }

            // Carry any money already paid forward instead of refunding it.
            $this->carryPaymentsForward($appointment, $replacement, $request->user()->id);

            $appointment->status = 'rescheduled';
            $appointment->reschedule_reason = $replacement->reschedule_reason;
            $appointment->save();

            $this->notifications->providerAppointmentRescheduled($appointment);

            DB::commit();
        } catch (\Exception $e) {
            DB::rollBack();
            return response()->json(['message' => 'Failed to reschedule appointment.', 'error' => $e->getMessage()], 500);
        }

        // The provider notice went out inside the transaction above (the job's
        // afterCommit handles the ordering). The customer's does not, because
        // it has to describe the *replacement* row, and that row only exists once
        // this has committed.
        $this->notifications->bookingRescheduled(
            $replacement,
            $replacement->salon?->name ?? 'the salon',
            $this->dateTimeLabel($replacement),
        );

        return response()->json([
            'message' => $window['free_reschedule']
                ? 'Appointment rescheduled free of cost.'
                : 'Appointment rescheduled successfully.',
            'appointment' => $this->presentBooking($replacement->fresh($this->bookingRelations())),
        ]);
    }
    /**
     * Issue the check-in QR the salon scans to start the appointment.
     *
     * Only inside the check-in window — from the booked start less SuperAdmin's
     * early start allowance, until the end of the appointment's day. Each code
     * still lives for `qr_validity_minutes` so a screenshot cannot be passed
     * around all day, but never past midnight: the day's no-show sweep is what
     * closes an unattended booking, and a code must not outlive it.
     */
    public function generateQr(Request $request, $id)
    {
        $appointment = Appointment::where('customer_id', $request->user()->id)->findOrFail($id);

        $window = $this->policy->checkInWindow($appointment);

        if (! $window['allowed']) {
            return response()->json([
                'message' => $window['reason'],
                'available_from' => $appointment->status === 'scheduled'
                    ? $window['opens_at']->toIso8601String()
                    : null,
            ], 400);
        }

        $validityMins = max(1, (int) PlatformPolicySetting::value('qr_validity_minutes'));

        // Generate a random token
        $rawToken = Str::random(32);

        $appointment->qr_token_hash = hash('sha256', $rawToken);
        $appointment->qr_generated_at = now();
        $appointment->qr_expires_at = now()->addMinutes($validityMins)->min($window['closes_at']);
        $appointment->save();

        return response()->json([
            'message' => 'QR Code generated successfully.',
            'qr_token' => $rawToken, // The frontend will encode this string into a QR graphic
            'expires_at' => $appointment->qr_expires_at
        ]);
    }

    /**
     * Everything the bookings list and detail views need.
     */
    private function bookingRelations(): array
    {
        return [
            'salon:id,name,address',
            'services.service.template:id,name,estimated_duration_minutes',
            'services.combo:id,name,will_refund_advance_if_cancelled',
            'appointedProvider.user:id,name',
            'salonClosure:id,closed_date,reason',
            // Every card asks whether it has been rated; without this the list
            // would run one query per booking to find out.
            'review',
            // Extras added in the chair — itemised for the customer, never
            // folded into the booked lines.
            'serviceAdditions.service.template:id,name,estimated_duration_minutes',
            'serviceAdditions.provider.user:id,name',
            // So the bookings list can offer the receipt without a query per
            // card.
            'invoice:id,appointment_id,invoice_number,issued_at',
            'firstTimeOffer:id,name,discount_type,discount_value',
        ];
    }

    /**
     * The receipt for this visit, or null when none was issued.
     *
     * The URL is signed rather than authenticated because the app opens it in a
     * WebView, which cannot carry a bearer token — see Invoice::temporaryUrl.
     * Regenerated on read, so a link the customer sat on for weeks still works
     * instead of having expired on them.
     */
    private function invoiceState(Appointment $appointment): ?array
    {
        // An invoice is only generated and available when the booking has been completed.
        if ($appointment->status !== 'completed') {
            return null;
        }

        $invoice = $appointment->relationLoaded('invoice')
            ? $appointment->invoice
            : Invoice::where('appointment_id', $appointment->id)->first();

        if (! $invoice) {
            try {
                $invoice = $this->invoices->issueFor($appointment);
            } catch (\Throwable $e) {
                // Non-blocking fallback
            }
        }

        if (! $invoice) {
            return null;
        }

        return [
            'number' => $invoice->invoice_number,
            'issued_at' => $invoice->issued_at?->toIso8601String(),
            'url' => $invoice->temporaryUrl(),
        ];
    }

    /**
     * Flatten an appointment into the shape the customer app renders, with the
     * policy decisions resolved server-side so the app never has to guess.
     */
    private function presentBooking(Appointment $appointment): array
    {
        $cancelWindow = $this->policy->cancellationWindow($appointment);
        $rescheduleWindow = $this->policy->rescheduleWindow($appointment);
        $qrWindow = $this->policy->checkInWindow($appointment);
        $refund = $this->policy->refundBreakdown($appointment);
        $date = Carbon::parse($appointment->appointment_date)->format('Y-m-d');

        $services = $appointment->services->map(fn ($line) => [
            'id' => $line->id,
            'name' => $line->service->template->name ?? 'Service',
            'combo_name' => $line->combo->name ?? null,
            'price' => (float) $line->price_at_booking,
            'original_price' => (float) ($line->original_service_price ?? $line->price_at_booking),
            'first_time_discount_amount' => (float) ($line->first_time_discount_amount ?? 0),
            'duration_minutes' => (int) $line->duration_minutes_at_booking,
            'line_status' => $line->line_status,
        ])->values();

        // Anything the salon added while the customer was in the chair. Kept as
        // its own list so the app can show it apart from what was booked —
        // the customer should always be able to see exactly what was added,
        // by whom, and what it cost.
        $additions = $appointment->serviceAdditions
            ->filter(fn ($addition) => $addition->isLive())
            ->map(fn ($addition) => [
                'id' => $addition->id,
                'name' => $addition->service->template->name ?? 'Service',
                'price' => (float) $addition->price_at_addition,
                'duration_minutes' => (int) $addition->duration_minutes_at_addition,
                'provider_name' => $addition->provider->user->name ?? null,
                'added_at' => $addition->added_at,
            ])->values();

        $bookedTotal = (float) $appointment->services
            ->where('line_status', '!=', 'cancelled')
            ->sum('price_at_booking');
        $addedTotal = (float) $appointment->serviceAdditions
            ->filter(fn ($addition) => $addition->isLive())
            ->sum('price_at_addition');

        $providerPhone = null;
        if ($appointment->status === 'scheduled' && now()->greaterThanOrEqualTo($qrWindow['opens_at']) && now()->lessThanOrEqualTo($qrWindow['closes_at'])) {
            $providerPhone = $appointment->appointedProvider?->user?->phone;
        }

        return [
            'id' => $appointment->id,
            'status' => $appointment->status,
            'salon' => [
                'id' => $appointment->salon_id,
                'name' => $appointment->salon->name ?? 'Salon',
                'address' => $appointment->salon->address ?? null,
                // The salon's own contact number, so a customer with an upcoming
                // booking can call the salon from the card. This is the business
                // line the salon lists publicly; it is deliberately not the
                // owner's personal number, which the app never reads.
                'phone' => $appointment->salon->phone_num ?? null,
                'latitude' => $appointment->salon->latitude !== null
                    ? (float) $appointment->salon->latitude
                    : null,
                'longitude' => $appointment->salon->longitude !== null
                    ? (float) $appointment->salon->longitude
                    : null,
            ],
            'provider_name' => $appointment->appointedProvider->user->name ?? 'Any available staff',
            'provider_phone' => $providerPhone,
            'appointment_date' => $date,
            'start_time' => substr($appointment->start_time, 0, 5),
            'end_time' => substr($appointment->end_time, 0, 5),
            'services' => $services,
            'added_services' => $additions,
            'booked_total' => round($bookedTotal, 2),
            'added_total' => round($addedTotal, 2),
            'total_amount' => (float) $appointment->total_amount,
            'advance_paid' => (float) $appointment->advance_amount,
            'balance_amount' => (float) $appointment->balance_amount,
            'final_billed_amount' => $appointment->final_billed_amount !== null
                ? (float) $appointment->final_billed_amount
                : null,
            'payment_option' => $appointment->payment_option,
            'first_time_discount_amount' => (float) ($appointment->first_time_discount_amount ?? 0),
            'first_time_offer_id' => $appointment->first_time_offer_id,
            'first_time_offer' => $appointment->firstTimeOffer ? [
                'id' => $appointment->firstTimeOffer->id,
                'name' => $appointment->firstTimeOffer->name,
                'discount_type' => $appointment->firstTimeOffer->discount_type,
                'discount_value' => (float) $appointment->firstTimeOffer->discount_value,
            ] : null,
            'invoice' => $this->invoiceState($appointment),
            'cancellation_reason' => $appointment->cancellation_reason,
            'rescheduled_from_id' => $appointment->rescheduled_from_id,

            // The salon closed this day. The booking still holds the money and
            // the services — the customer just has to pick a new slot.
            'needs_reschedule' => $appointment->status === BookingPolicyService::AWAITING_RESCHEDULE,
            'released_by_salon' => $this->policy->wasReleasedBySalon($appointment),
            'closure_reason' => $appointment->salonClosure->reason ?? null,

            // What the customer may do right now.
            'can_cancel' => $cancelWindow['allowed'],
            'can_reschedule' => $rescheduleWindow['allowed'],
            'cancel_blocked_reason' => $cancelWindow['reason'],
            'reschedule_blocked_reason' => $rescheduleWindow['reason'],
            'cancellation_cutoff_minutes' => $cancelWindow['cutoff_minutes'],
            'reschedule_cutoff_minutes' => $rescheduleWindow['cutoff_minutes'],
            'free_reschedule' => $rescheduleWindow['free_reschedule'],
            'refundable_advance' => $refund['refundable'],
            'forfeited_advance' => $refund['forfeited'],
            // The check-in QR. `qr_available_from` lets the app say "available
            // at 4:30 PM" on a booking whose window has not opened yet, instead
            // of hiding the button and leaving the customer to guess.
            'can_generate_qr' => $qrWindow['allowed'],
            'qr_blocked_reason' => $qrWindow['reason'],
            'qr_available_from' => $appointment->status === 'scheduled'
                ? $qrWindow['opens_at']->toIso8601String()
                : null,
            'qr_available_until' => $qrWindow['closes_at']->toIso8601String(),
        ] + $this->reviewState($appointment);
    }

    /**
     * Whether this visit can still be rated, and what was said if it already
     * was.
     *
     * Decided here rather than in the app so the button on a booking card and
     * the prompt that appears on opening can never disagree — both read the
     * same rule out of ReviewService.
     *
     * @return array<string, mixed>
     */
    private function reviewState(Appointment $appointment): array
    {
        $reviews = app(\App\Services\ReviewService::class);
        $existing = $appointment->review;
        $can = $reviews->reviewability($appointment);

        return [
            'can_review' => $can['allowed'],
            // Only worth showing when it explains a missing button — "already
            // reviewed" has its own display, and a visit that was never
            // eligible does not need an excuse.
            'review_blocked_reason' => $can['allowed'] || $existing ? null : $can['reason'],
            'review' => $existing ? [
                'rating' => $existing->rating,
                'comment' => $existing->comment,
                'age_label' => $reviews->ageLabel($existing->created_at),
            ] : null,
        ];
    }

    /**
     * Record a refund against the successful payments of an appointment, and
     * ask the gateway to send the money back.
     *
     * No-op when nothing was actually captured, so the ledger never invents a
     * refund for money that was never taken. A refund the gateway would not
     * accept stays `pending` for someone to chase rather than being recorded as
     * done.
     */
    private function raiseRefund(Appointment $appointment, float $amount, string $reason, string $userId): void
    {
        $ids = $this->createPendingRefundRecords($appointment, $amount, $reason, $userId);
        foreach ($ids as $id) {
            $this->payments->processPendingRefund($id);
        }
    }

    private function createPendingRefundRecords(Appointment $appointment, float $amount, string $reason, string $userId): array
    {
        if ($amount <= 0) {
            return [];
        }

        $payments = DB::table('payments')
            ->where('appointment_id', $appointment->id)
            ->where('status', 'success')
            ->orderBy('created_at')
            ->get();

        $remaining = $amount;
        $createdIds = [];

        foreach ($payments as $payment) {
            if ($remaining <= 0) {
                break;
            }

            $slice = min($remaining, (float) $payment->amount);
            $refundRecordId = (string) Str::uuid();

            DB::table('payment_refunds')->insert([
                'id' => $refundRecordId,
                'payment_id' => $payment->id,
                'appointment_id' => $appointment->id,
                'amount' => $slice,
                'reason' => $reason,
                'gateway_refund_id' => null,
                'status' => 'pending',
                'initiated_by' => $userId,
                'metadata' => json_encode([
                    'idempotency_key' => "refund:{$payment->id}",
                ]),
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            $createdIds[] = $refundRecordId;
            $remaining -= $slice;
        }

        return $createdIds;
    }

    /**
     * "Sep 26, 2026 at 4:30 PM".
     *
     * One place, because a confirmation, a cancellation and a reschedule all
     * quote the same booking and a customer who reads two of them in a week
     * should not see two formats. The service has the same helper; this copy
     * exists so the controller can label an appointment it is only responding
     * to, without the service having to expose a formatting method for every
     * caller that wants to print something.
     */
    private function dateTimeLabel(Appointment $appointment): string
    {
        return Carbon::parse($appointment->appointment_date)->format('M d, Y')
            .' at '
            .Carbon::parse($appointment->start_time)->format('h:i A');
    }

    /**
     * Move successful payments of the original appointment onto the new one,
     * so a reschedule never looks like a refund plus a fresh charge.
     */
    private function carryPaymentsForward(Appointment $from, Appointment $to, string $userId): void
    {
        $payments = DB::table('payments')
            ->where('appointment_id', $from->id)
            ->where('status', 'success')
            ->get();

        foreach ($payments as $payment) {
            DB::table('payment_allocations')->insert([
                'id' => (string) Str::uuid(),
                'payment_id' => $payment->id,
                'appointment_id' => $to->id,
                'allocated_amount' => $payment->amount,
                'allocation_type' => 'reschedule_carry_forward',
                'created_by' => $userId,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }
}
