<?php

namespace App\Services;

use App\Models\Appointment;
use App\Models\FirstTimeOffer;
use App\Models\FirstTimeOfferRedemption;
use App\Models\Service;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Authoritative evaluation service for BookALook first-time customer discounts.
 *
 * This service determines customer qualification under platform-wide and salon-specific
 * scopes, validates promotional schedules and campaign caps, evaluates line-item minimum
 * conditions, and allocates discounts deterministically across eligible loose cart services.
 */
class CustomerOfferEligibilityService
{
    /**
     * Resolve customer UUID and deterministic phone hash from User model or UUID string.
     *
     * @return array{0: string, 1: ?string} [customerId, phoneHash]
     */
    public function resolveCustomerIdentity(User|string $customer): array
    {
        $customerId = $customer instanceof User ? $customer->id : $customer;
        $phoneHash = null;

        if ($customer instanceof User) {
            $phoneHash = FirstTimeOffer::hashPhone($customer->phone);
        } else {
            $user = User::find($customerId);
            if ($user && ! empty($user->phone)) {
                $phoneHash = FirstTimeOffer::hashPhone($user->phone);
            }
        }

        return [$customerId, $phoneHash];
    }

    /**
     * Determine if a customer has any qualifying prior booking history.
     *
     * A qualifying booking is any appointment that became a real booking:
     * - scheduled, in_progress, completed, rescheduled, awaiting_reschedule, no_show
     * - OR cancelled by customer, salon, partner, or admin (genuine cancellation)
     * - OR cancelled with a successful payment transaction recorded
     *
     * Inactive holds and abandoned payment checkouts (status = pending_payment, or
     * status = cancelled with cancelled_by = 'system' and no successful payment) DO NOT
     * count as qualifying bookings and do not disqualify the customer.
     *
     * Uses customer_phone_hash alongside customer_id to ensure customer identity
     * continuity even if an account was deleted and re-registered with the same phone.
     */
    public function hasQualifyingBooking(User|string $customer, string $scope, ?string $salonId = null): bool
    {
        [$customerId, $phoneHash] = $this->resolveCustomerIdentity($customer);

        $query = Appointment::where(function ($userQ) use ($customerId, $phoneHash) {
            $userQ->where('customer_id', $customerId);
            if ($phoneHash) {
                $userQ->orWhere('customer_phone_hash', $phoneHash);
            }
        })
            ->where(function ($q) {
                // 1. Definite active/completed booking statuses
                $q->whereIn('status', [
                    'scheduled',
                    'in_progress',
                    'completed',
                    'rescheduled',
                    'awaiting_reschedule',
                    'no_show',
                ])
                // 2. Genuine cancellations (customer/partner/salon cancellations or bookings with verified payment)
                    ->orWhere(function ($cancelledQuery) {
                        $cancelledQuery->where('status', 'cancelled')
                            ->where(function ($cq) {
                                $cq->whereIn('cancelled_by', ['customer', 'salon', 'partner', 'admin'])
                                    ->orWhereExists(function ($paymentSubquery) {
                                        $paymentSubquery->select(DB::raw(1))
                                            ->from('payments')
                                            ->whereColumn('payments.appointment_id', 'appointments.id')
                                            ->where('payments.status', 'success');
                                    });
                            });
                    });
            });

        if ($scope === FirstTimeOffer::SCOPE_NEW_TO_SALON && $salonId) {
            $query->where('salon_id', $salonId);
        }

        return $query->exists();
    }

    /**
     * Check if a customer has already committed a redemption for this offer.
     * Checks both customer_id and customer_phone_hash for identity continuity.
     */
    public function hasCommittedRedemption(User|string $customer, string $offerId): bool
    {
        [$customerId, $phoneHash] = $this->resolveCustomerIdentity($customer);

        $query = FirstTimeOfferRedemption::where('offer_id', $offerId)
            ->where('status', FirstTimeOfferRedemption::STATUS_COMMITTED);

        $query->where(function ($q) use ($customerId, $phoneHash) {
            $q->where('customer_id', $customerId);
            if ($phoneHash) {
                $q->orWhere('customer_phone_hash', $phoneHash);
            }
        });

        return $query->exists();
    }

    /**
     * Check if a customer has an in-flight unexpired reservation for this offer.
     */
    public function hasActiveReservation(User|string $customer, string $offerId): bool
    {
        [$customerId, $phoneHash] = $this->resolveCustomerIdentity($customer);

        $query = FirstTimeOfferRedemption::where('offer_id', $offerId)
            ->where('status', FirstTimeOfferRedemption::STATUS_RESERVED);

        $query->where(function ($q) use ($customerId, $phoneHash) {
            $q->where('customer_id', $customerId);
            if ($phoneHash) {
                $q->orWhere('customer_phone_hash', $phoneHash);
            }
        });

        return $query->exists();
    }

    /**
     * Determine if an offer has reached its campaign limit, accounting for both
     * committed redemptions and in-flight active reservations to prevent oversubscription.
     */
    public function isCampaignLimitReached(FirstTimeOffer $offer, bool $includeActiveReservations = true): bool
    {
        if ($offer->max_redemptions === null) {
            return false;
        }

        $totalConsumed = (int) $offer->current_redemptions;

        if ($includeActiveReservations) {
            $activeReservations = FirstTimeOfferRedemption::where('offer_id', $offer->id)
                ->where('status', FirstTimeOfferRedemption::STATUS_RESERVED)
                ->count();
            $totalConsumed += $activeReservations;
        }

        return $totalConsumed >= (int) $offer->max_redemptions;
    }

    /**
     * Check if a specific customer qualifies for an offer at a particular salon.
     */
    public function isCustomerEligibleForOffer(
        User|string|null $customer,
        FirstTimeOffer $offer,
        string $salonId
    ): bool {
        if (! $customer) {
            return false;
        }

        // 1. Offer must be active and within valid schedule
        if (! $offer->is_active || ! $offer->isCurrentlyValid()) {
            return false;
        }

        // 2. Offer must have at least one explicitly targeted service template
        if (! $offer->serviceTemplates()->exists()) {
            return false;
        }

        // 3. Salon must participate in this offer
        if (! $offer->participates($salonId)) {
            return false;
        }

        // 4. Offer campaign limit must not be reached (including in-flight holds)
        if ($this->isCampaignLimitReached($offer, true)) {
            return false;
        }

        // 5. Customer must not have previously committed this offer
        if ($this->hasCommittedRedemption($customer, $offer->id)) {
            return false;
        }

        // 6. Customer must not have an active hold on this offer
        if ($this->hasActiveReservation($customer, $offer->id)) {
            return false;
        }

        // 7. Customer must qualify under the offer scope (no qualifying prior booking)
        if ($this->hasQualifyingBooking($customer, $offer->scope, $salonId)) {
            return false;
        }

        return true;
    }

    /**
     * Retrieve all active offers that the customer and salon currently qualify for.
     *
     * @return Collection<int, FirstTimeOffer>
     */
    public function getEligibleOffersForCustomerAndSalon(
        User|string|null $customer,
        string $salonId
    ): Collection {
        if (! $customer) {
            return collect();
        }

        $now = Carbon::now();

        // Load candidate offers that are active and in date range
        $candidates = FirstTimeOffer::with(['serviceTemplates', 'participatingSalons'])
            ->where('is_active', true)
            ->where(function ($q) use ($now) {
                $q->whereNull('starts_at')->orWhere('starts_at', '<=', $now);
            })
            ->where(function ($q) use ($now) {
                $q->whereNull('ends_at')->orWhere('ends_at', '>=', $now);
            })
            // Offers belong to the salon that made them and apply there only.
            // The old platform-wide offers (no salon) are retired.
            ->where('salon_id', $salonId)
            ->get();

        return $candidates->filter(function (FirstTimeOffer $offer) use ($customer, $salonId) {
            return $this->isCustomerEligibleForOffer($customer, $offer, $salonId);
        })->values();
    }

    /**
     * Check if a specific service instance qualifies for an offer.
     */
    public function isServiceEligibleForOffer(Service $service, FirstTimeOffer $offer): bool
    {
        if (! $service->is_active || $service->deleted_at !== null) {
            return false;
        }

        // Must target the service's template
        if (! $offer->targetsTemplate($service->template_id)) {
            return false;
        }

        // Minimum eligible service price
        if ($offer->min_service_price !== null && (float) $offer->min_service_price > 0) {
            if ((float) $service->price < (float) $offer->min_service_price) {
                return false;
            }
        }

        return true;
    }

    /**
     * Evaluate an offer on candidate loose cart lines and calculate allocated discounts.
     *
     * @param  array<int, array{service_id: string, template_id: string, price: float, quantity: int, line_total: float}>  $looseLines
     * @return array{
     *   applicable: bool,
     *   offer: FirstTimeOffer,
     *   total_discount: float,
     *   eligible_subtotal: float,
     *   allocated_lines: array<string, array{service_id: string, line_discount: float, per_unit_discount: float, final_line_price: float}>
     * }
     */
    public function evaluateOfferOnCartLines(
        FirstTimeOffer $offer,
        array $looseLines,
        float $bookingListTotal
    ): array {
        $eligibleLines = [];
        $eligibleSubtotal = 0.0;
        $potentialLineDiscounts = [];
        $lineTotals = [];

        $targetTemplateIds = $offer->serviceTemplates->pluck('id')->all();
        $minServicePrice = (float) ($offer->min_service_price ?? 0.0);

        // 1. Identify eligible lines and compute unconstrained potential line discounts
        foreach ($looseLines as $line) {
            $serviceId = $line['service_id'];
            $templateId = $line['template_id'];
            $price = (float) $line['price'];
            $qty = max(1, (int) $line['quantity']);
            $lineTotal = round($price * $qty, 2);

            $lineTotals[$serviceId] = $lineTotal;

            // Template targeting check
            if (! in_array($templateId, $targetTemplateIds, true)) {
                continue;
            }

            // Minimum service price check
            if ($minServicePrice > 0 && $price < $minServicePrice) {
                continue;
            }

            $eligibleLines[$serviceId] = $line;
            $eligibleSubtotal += $lineTotal;

            if ($offer->discount_type === FirstTimeOffer::TYPE_PERCENTAGE) {
                $pct = (float) $offer->discount_value;
                $potential = round($lineTotal * ($pct / 100.0), 2);
            } else {
                // Flat discount per eligible service item
                $flatUnit = min((float) $offer->discount_value, $price);
                $potential = round($flatUnit * $qty, 2);
            }

            $potentialLineDiscounts[$serviceId] = min($potential, $lineTotal);
        }

        // 2. Minimum eligible subtotal check
        if ($offer->min_eligible_subtotal !== null && (float) $offer->min_eligible_subtotal > 0) {
            if ($eligibleSubtotal < (float) $offer->min_eligible_subtotal) {
                return [
                    'applicable' => false,
                    'offer' => $offer,
                    'total_discount' => 0.0,
                    'eligible_subtotal' => round($eligibleSubtotal, 2),
                    'allocated_lines' => [],
                ];
            }
        }

        // 3. Minimum total booking subtotal check
        if ($offer->min_total_booking_subtotal !== null && (float) $offer->min_total_booking_subtotal > 0) {
            if ($bookingListTotal < (float) $offer->min_total_booking_subtotal) {
                return [
                    'applicable' => false,
                    'offer' => $offer,
                    'total_discount' => 0.0,
                    'eligible_subtotal' => round($eligibleSubtotal, 2),
                    'allocated_lines' => [],
                ];
            }
        }

        $sumPotential = array_sum($potentialLineDiscounts);
        if ($sumPotential <= 0) {
            return [
                'applicable' => false,
                'offer' => $offer,
                'total_discount' => 0.0,
                'eligible_subtotal' => round($eligibleSubtotal, 2),
                'allocated_lines' => [],
            ];
        }

        // 4. Enforce booking-level cap
        $cap = $offer->discount_type === FirstTimeOffer::TYPE_FLAT
            ? ($offer->flat_booking_cap !== null ? (float) $offer->flat_booking_cap : ($offer->max_discount_cap !== null ? (float) $offer->max_discount_cap : null))
            : ($offer->max_discount_cap !== null ? (float) $offer->max_discount_cap : null);

        $actualTotal = $cap !== null ? min($sumPotential, $cap) : $sumPotential;
        $actualTotal = round($actualTotal, 2);

        // 5. Deterministically allocate actualTotal across eligible lines
        $allocatedDiscounts = $this->allocateDiscountDeterministically(
            $actualTotal,
            $potentialLineDiscounts,
            $lineTotals
        );

        $allocatedLines = [];
        foreach ($looseLines as $line) {
            $serviceId = $line['service_id'];
            $qty = max(1, (int) $line['quantity']);
            $lineTotal = round((float) $line['price'] * $qty, 2);
            $lineDiscount = $allocatedDiscounts[$serviceId] ?? 0.0;
            $finalPrice = max(0.0, round($lineTotal - $lineDiscount, 2));

            $allocatedLines[$serviceId] = [
                'service_id' => $serviceId,
                'line_discount' => $lineDiscount,
                'per_unit_discount' => $qty > 0 ? round($lineDiscount / $qty, 2) : 0.0,
                'final_line_price' => $finalPrice,
            ];
        }

        return [
            'applicable' => $actualTotal > 0,
            'offer' => $offer,
            'total_discount' => $actualTotal,
            'eligible_subtotal' => round($eligibleSubtotal, 2),
            'allocated_lines' => $allocatedLines,
        ];
    }

    /**
     * Find the single best first-time offer for a cart from all applicable offers.
     *
     * Non-stacking rule: if multiple offers match, select the one producing the greatest
     * total discount. Tie-breakers: higher discount_value, earlier created_at, then offer ID.
     */
    public function findBestOfferForCart(
        User|string|null $customer,
        string $salonId,
        array $looseLines,
        float $bookingListTotal
    ): ?array {
        if (! $customer || empty($looseLines)) {
            return null;
        }

        $eligibleOffers = $this->getEligibleOffersForCustomerAndSalon($customer, $salonId);

        if ($eligibleOffers->isEmpty()) {
            return null;
        }

        $evaluated = [];

        foreach ($eligibleOffers as $offer) {
            $result = $this->evaluateOfferOnCartLines($offer, $looseLines, $bookingListTotal);
            if ($result['applicable'] && $result['total_discount'] > 0) {
                $evaluated[] = $result;
            }
        }

        if (empty($evaluated)) {
            return null;
        }

        // Sort descending: greatest discount first, then stable tie-breakers
        usort($evaluated, function ($a, $b) {
            // 1. Greatest discount amount
            if (abs($b['total_discount'] - $a['total_discount']) >= 0.005) {
                return $b['total_discount'] <=> $a['total_discount'];
            }

            // 2. Higher configured discount value
            $valA = (float) $a['offer']->discount_value;
            $valB = (float) $b['offer']->discount_value;
            if (abs($valB - $valA) >= 0.005) {
                return $valB <=> $valA;
            }

            // 3. Earlier created_at
            $timeA = $a['offer']->created_at?->timestamp ?? 0;
            $timeB = $b['offer']->created_at?->timestamp ?? 0;
            if ($timeA !== $timeB) {
                return $timeA <=> $timeB;
            }

            // 4. Stable UUID ordering
            return strcmp($a['offer']->id, $b['offer']->id);
        });

        return $evaluated[0];
    }

    /**
     * Find the single best offer for an individual service card in catalog preview.
     */
    public function findBestOfferForSingleService(
        User|string|null $customer,
        string $salonId,
        Service $service
    ): ?array {
        if (! $customer || ! $service->is_active || $service->deleted_at !== null) {
            return null;
        }

        $eligibleOffers = $this->getEligibleOffersForCustomerAndSalon($customer, $salonId);

        if ($eligibleOffers->isEmpty()) {
            return null;
        }

        $candidates = [];

        $price = (float) $service->price;
        $templateId = $service->template_id;

        foreach ($eligibleOffers as $offer) {
            if (! $offer->targetsTemplate($templateId)) {
                continue;
            }

            if ($offer->min_service_price !== null && (float) $offer->min_service_price > 0) {
                if ($price < (float) $offer->min_service_price) {
                    continue;
                }
            }

            // Potential discount calculation for single service
            if ($offer->discount_type === FirstTimeOffer::TYPE_PERCENTAGE) {
                $pct = (float) $offer->discount_value;
                $potential = round($price * ($pct / 100.0), 2);
                $cap = $offer->max_discount_cap !== null ? (float) $offer->max_discount_cap : null;
            } else {
                $potential = min((float) $offer->discount_value, $price);
                $cap = $offer->flat_booking_cap !== null ? (float) $offer->flat_booking_cap : ($offer->max_discount_cap !== null ? (float) $offer->max_discount_cap : null);
            }

            $discountAmount = $cap !== null ? min($potential, $cap) : $potential;
            $discountAmount = min($discountAmount, $price);

            if ($discountAmount <= 0) {
                continue;
            }

            $candidates[] = [
                'offer' => $offer,
                'discount_amount' => round($discountAmount, 2),
                'discounted_price' => round(max(0.0, $price - $discountAmount), 2),
            ];
        }

        if (empty($candidates)) {
            return null;
        }

        usort($candidates, function ($a, $b) {
            if (abs($b['discount_amount'] - $a['discount_amount']) >= 0.005) {
                return $b['discount_amount'] <=> $a['discount_amount'];
            }
            $valA = (float) $a['offer']->discount_value;
            $valB = (float) $b['offer']->discount_value;
            if (abs($valB - $valA) >= 0.005) {
                return $valB <=> $valA;
            }

            return strcmp($a['offer']->id, $b['offer']->id);
        });

        $winner = $candidates[0];
        $offer = $winner['offer'];

        return [
            'offer_id' => $offer->id,
            'offer_name' => $offer->name,
            'scope' => $offer->scope,
            'discount_type' => $offer->discount_type,
            'discount_value' => (float) $offer->discount_value,
            'discount_amount' => $winner['discount_amount'],
            'discounted_price' => $winner['discounted_price'],
            'discount_label' => (function () use ($offer) {
                $val = (float) $offer->discount_value;
                $formatted = ($val == (int) $val) ? (string) (int) $val : (string) $val;

                return $offer->discount_type === FirstTimeOffer::TYPE_PERCENTAGE
                    ? "{$formatted}% OFF"
                    : "₹{$formatted} OFF";
            })(),
            'is_capped' => (bool) ($offer->max_discount_cap !== null || $offer->flat_booking_cap !== null),
            'max_discount_cap' => $offer->max_discount_cap ? (float) $offer->max_discount_cap : null,
            'min_service_price' => $offer->min_service_price ? (float) $offer->min_service_price : 0.0,
            'min_eligible_subtotal' => $offer->min_eligible_subtotal ? (float) $offer->min_eligible_subtotal : 0.0,
            'min_total_booking_subtotal' => $offer->min_total_booking_subtotal ? (float) $offer->min_total_booking_subtotal : 0.0,
        ];
    }

    /**
     * Deterministically allocates an aggregate discount across lines using largest remainder apportionment.
     *
     * @param  array<string, float>  $potentialLineDiscounts  Service ID -> Potential discount in rupees
     * @param  array<string, float>  $lineTotals  Service ID -> Line total in rupees
     * @return array<string, float> Service ID -> Allocated discount in rupees
     */
    public function allocateDiscountDeterministically(
        float $actualTotal,
        array $potentialLineDiscounts,
        array $lineTotals
    ): array {
        $totalPaise = (int) round($actualTotal * 100);

        if ($totalPaise <= 0 || empty($potentialLineDiscounts)) {
            $res = [];
            foreach (array_keys($potentialLineDiscounts) as $id) {
                $res[$id] = 0.0;
            }

            return $res;
        }

        $potentialPaise = [];
        foreach ($potentialLineDiscounts as $id => $val) {
            $potentialPaise[$id] = (int) round($val * 100);
        }

        $sumPotentialPaise = array_sum($potentialPaise);

        // If actual meets or exceeds potential, everyone gets their full potential
        if ($totalPaise >= $sumPotentialPaise) {
            $allocated = [];
            foreach ($potentialPaise as $id => $paise) {
                $maxPaise = (int) round(($lineTotals[$id] ?? 0.0) * 100);
                $allocated[$id] = round(min($paise, $maxPaise) / 100.0, 2);
            }

            return $allocated;
        }

        // Proportional apportionment (Hamilton-Webster) in minor units (paise)
        $floorShare = [];
        $remainders = [];

        foreach ($potentialPaise as $id => $paise) {
            $exact = ($paise * $totalPaise) / $sumPotentialPaise;
            $floor = (int) floor($exact);
            $floorShare[$id] = $floor;
            $remainders[$id] = $exact - $floor;
        }

        $allocatedPaiseSum = array_sum($floorShare);
        $remainderPaise = $totalPaise - $allocatedPaiseSum;

        // Sort IDs deterministically: highest remainder first, tie-break by ID ascending
        $keys = array_keys($potentialPaise);
        usort($keys, function ($a, $b) use ($remainders) {
            if ($remainders[$a] > $remainders[$b]) {
                return -1;
            }
            if ($remainders[$a] < $remainders[$b]) {
                return 1;
            }

            return strcmp($a, $b);
        });

        for ($i = 0; $i < $remainderPaise; $i++) {
            $id = $keys[$i % count($keys)];
            $floorShare[$id]++;
        }

        $result = [];
        foreach ($floorShare as $id => $paise) {
            $maxPaise = (int) round(($lineTotals[$id] ?? 0.0) * 100);
            $finalPaise = min($paise, $maxPaise);
            $result[$id] = round($finalPaise / 100.0, 2);
        }

        return $result;
    }
}
