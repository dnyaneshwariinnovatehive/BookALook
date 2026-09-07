<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\Appointment;
use App\Models\AppointmentService;
use App\Models\Cart;
use App\Models\CartItem;
use App\Models\PlatformPolicySetting;
use App\Models\ServiceProvider;
use App\Models\Salon;
use App\Services\AvailabilityService;
use App\Services\BookingPaymentService;
use App\Services\BookingPolicyService;
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
    ) {
    }

    /**
     * Staff of the salon, flagged against the services currently in the cart.
     * Providers who cannot perform every service are returned with
     * is_eligible = false so the app can grey them out.
     */
    public function getProviders(Request $request, $salon_id)
    {
        $cart = $this->activeCart($request, $salon_id);
        $requirements = $cart
            ? $this->availability->summariseCart($cart)
            : ['service_ids' => [], 'duration' => AvailabilityService::SLOT_MINUTES, 'total' => 0, 'advance' => 0];

        $providers = $this->availability->providersForSalon($salon_id, $requirements['service_ids']);

        return response()->json([
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
            'provider_id' => 'nullable|exists:service_providers,id' // null means 'Any Available'
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
            'provider_id' => 'nullable|exists:service_providers,id' // null means 'Any Available'
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $user = $request->user();
        $cart = $this->activeCart($request, $salon_id);

        if (!$cart || $cart->items->isEmpty()) {
            return response()->json(['message' => 'Cart is empty.'], 400);
        }

        $requirements = $this->availability->summariseCart($cart);
        $candidates = $this->candidateProviders($salon_id, $requirements['service_ids'], $request->provider_id);

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

                for ($i = 0; $i < $line['quantity']; $i++) {
                    $this->createAppointmentService($appointment->id, $service, (float) $line['price']);
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

        if ($appointment->status !== 'pending_payment') {
            return response()->json(['message' => 'This booking is not awaiting payment.'], 400);
        }

        if ($appointment->payment_hold_expires_at && now()->greaterThan($appointment->payment_hold_expires_at)) {
            $this->payments->release($appointment, 'Payment was not completed in time.');

            return response()->json([
                'message' => 'The hold on your slot expired before the payment came through. Please book again.',
                'hold_expired' => true,
            ], 409);
        }

        $result = $this->payments->confirm($appointment, $paymentId, $signature, $request->user()->id);

        if (! $result['ok']) {
            return response()->json(['message' => $result['message']], 422);
        }

        $this->settleBooking($appointment, $this->activeCart($request, $appointment->salon_id));

        return response()->json([
            'message' => 'Payment received. Your appointment is confirmed.',
            'appointment' => $this->presentBooking($appointment->fresh()->load($this->bookingRelations())),
        ]);
    }

    /**
     * Turn a paid hold into a confirmed booking and retire the cart behind it.
     */
    private function settleBooking(Appointment $appointment, ?Cart $cart): void
    {
        DB::transaction(function () use ($appointment, $cart) {
            $appointment->forceFill([
                'status' => 'scheduled',
                'payment_hold_expires_at' => null,
            ])->save();

            if ($cart) {
                $cart->items()->delete();
                $cart->status = 'converted';
                $cart->save();
            }
        });
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
     * @return string[]|\Illuminate\Http\JsonResponse
     */
    private function candidateProviders(string $salonId, array $serviceIds, ?string $providerId)
    {
        $providers = $this->availability->providersForSalon($salonId, $serviceIds);
        $eligible = array_values(array_filter($providers, fn ($p) => $p['is_eligible']));

        if ($providerId === null) {
            // 'Any Available'
            if (empty($eligible)) {
                return response()->json([
                    'message' => 'No service provider at this salon can perform all the selected services.',
                ], 422);
            }

            return array_column($eligible, 'id');
        }

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

        return [$providerId];
    }

    private function createAppointmentService(string $appointmentId, $service, float $price, ?string $comboId = null): void
    {
        AppointmentService::create([
            'appointment_id' => $appointmentId,
            'service_id' => $service->id,
            'combo_id' => $comboId,
            'price_at_booking' => $price,
            'original_service_price' => $service->price,
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

            $this->raiseRefund(
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

        $date = Carbon::parse($appointment->appointment_date)->format('Y-m-d');

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
            $request->provider_id
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
            foreach ($appointment->services as $line) {
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

            DB::commit();
        } catch (\Exception $e) {
            DB::rollBack();
            return response()->json(['message' => 'Failed to reschedule appointment.', 'error' => $e->getMessage()], 500);
        }

        return response()->json([
            'message' => $window['free_reschedule']
                ? 'Appointment rescheduled free of cost.'
                : 'Appointment rescheduled successfully.',
            'appointment' => $this->presentBooking($replacement->fresh($this->bookingRelations())),
        ]);
    }

    /**
     * Generate QR code for same-day appointment.
     */
    public function generateQr(Request $request, $id)
    {
        $appointment = Appointment::where('customer_id', $request->user()->id)->findOrFail($id);

        if (! in_array($appointment->status, BookingPolicyService::ACTIVE_STATUSES, true)) {
            return response()->json(['message' => 'QR can only be generated for upcoming appointments.'], 400);
        }

        // Ensure it's for today
        if (Carbon::parse($appointment->appointment_date)->format('Y-m-d') !== now()->format('Y-m-d')) {
            return response()->json(['message' => 'QR can only be generated on the day of the appointment.'], 400);
        }

        $validityMins = (int) PlatformPolicySetting::value('qr_validity_minutes');

        // Generate a random token
        $rawToken = Str::random(32);

        $appointment->qr_token_hash = hash('sha256', $rawToken);
        $appointment->qr_generated_at = now();
        $appointment->qr_expires_at = now()->addMinutes($validityMins);
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
            'salon:id,name,address,phone_num',
            'services.service.template:id,name,estimated_duration_minutes',
            'services.combo:id,name,will_refund_advance_if_cancelled',
            'appointedProvider.user:id,name',
            'salonClosure:id,closed_date,reason',
            // Extras added in the chair — itemised for the customer, never
            // folded into the booked lines.
            'serviceAdditions.service.template:id,name,estimated_duration_minutes',
            'serviceAdditions.provider.user:id,name',
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
        $refund = $this->policy->refundBreakdown($appointment);
        $date = Carbon::parse($appointment->appointment_date)->format('Y-m-d');

        $services = $appointment->services->map(fn ($line) => [
            'id' => $line->id,
            'name' => $line->service->template->name ?? 'Service',
            'combo_name' => $line->combo->name ?? null,
            'price' => (float) $line->price_at_booking,
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

        return [
            'id' => $appointment->id,
            'status' => $appointment->status,
            'salon' => [
                'id' => $appointment->salon_id,
                'name' => $appointment->salon->name ?? 'Salon',
                'address' => $appointment->salon->address ?? null,
                'phone' => $appointment->salon->phone_num ?? null,
            ],
            'provider_name' => $appointment->appointedProvider->user->name ?? 'Any available staff',
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
            'can_generate_qr' => in_array($appointment->status, BookingPolicyService::ACTIVE_STATUSES, true)
                && $date === now()->format('Y-m-d'),
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
        if ($amount <= 0) {
            return;
        }

        $payments = DB::table('payments')
            ->where('appointment_id', $appointment->id)
            ->where('status', 'success')
            ->orderBy('created_at')
            ->get();

        $remaining = $amount;

        foreach ($payments as $payment) {
            if ($remaining <= 0) {
                break;
            }

            $slice = min($remaining, (float) $payment->amount);

            $refundId = $payment->gateway_transaction_id
                ? $this->payments->refund($payment->gateway_transaction_id, $slice, $reason)
                : null;

            DB::table('payment_refunds')->insert([
                'id' => (string) Str::uuid(),
                'payment_id' => $payment->id,
                'appointment_id' => $appointment->id,
                'amount' => $slice,
                'reason' => $reason,
                'gateway_refund_id' => $refundId,
                'status' => $refundId ? 'processed' : 'pending',
                'processed_at' => $refundId ? now() : null,
                'initiated_by' => $userId,
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            $remaining -= $slice;
        }
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
