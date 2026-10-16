<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\FirstTimeOffer;
use App\Models\PlatformPolicySetting;
use App\Models\Salon;
use App\Models\Service;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

class SalonOfferController extends Controller
{
    /**
     * Authorize that the current authenticated user owns/manages this salon.
     */
    private function authorizeSalonAdmin(string $salonId, Request $request): ?JsonResponse
    {
        $salon = Salon::find($salonId);
        if (! $salon) {
            return response()->json([
                'success' => false,
                'message' => 'Salon not found.',
            ], 404);
        }

        $user = $request->user();
        if (! $user || ($salon->admin_id !== $user->id && ! in_array($user->role, ['superadmin'], true))) {
            return response()->json([
                'success' => false,
                'message' => 'Unauthorized for this salon.',
            ], 403);
        }

        return null;
    }

    /**
     * Compute a user-facing offer status string.
     */
    public static function computeOfferStatus(FirstTimeOffer $offer): string
    {
        $now = Carbon::now();

        if (($offer->ends_at && $now->gt($offer->ends_at)) || $offer->isRedemptionLimitReached()) {
            return 'Expired';
        }

        if ($offer->starts_at && $now->lt($offer->starts_at)) {
            return 'Scheduled';
        }

        if (! $offer->is_active) {
            return 'Inactive';
        }

        return 'Active';
    }

    /**
     * Get available salon services, scope options, and platform limits.
     */
    public function options(string $salon_id, Request $request): JsonResponse
    {
        if ($authError = $this->authorizeSalonAdmin($salon_id, $request)) {
            return $authError;
        }

        // Services offered by this salon with their template and category details
        $services = Service::with(['template.category'])
            ->where('salon_id', $salon_id)
            ->where('is_active', true)
            ->get()
            ->map(function (Service $service) {
                return [
                    'id' => $service->id,
                    'service_template_id' => $service->template_id,
                    'name' => $service->template?->name ?? 'Custom Service',
                    'category' => $service->template?->category?->name ?? 'General',
                    'price' => (float) $service->price,
                ];
            });

        return response()->json([
            'success' => true,
            'data' => [
                'services' => $services,
                'scopes' => [
                    [
                        'key' => FirstTimeOffer::SCOPE_NEW_TO_PLATFORM,
                        'name' => 'First booking on BookALook',
                        'description' => 'Eligible only if the customer has no previous booking on the entire BookALook platform.',
                    ],
                    [
                        'key' => FirstTimeOffer::SCOPE_NEW_TO_SALON,
                        'name' => 'First booking at this salon',
                        'description' => 'Eligible only if the customer has no previous booking at your specific salon.',
                    ],
                ],
                'discount_types' => [
                    [
                        'key' => FirstTimeOffer::TYPE_PERCENTAGE,
                        'name' => 'Percentage Discount (%)',
                    ],
                    [
                        'key' => FirstTimeOffer::TYPE_FLAT,
                        'name' => 'Flat Discount (₹)',
                    ],
                ],
                'policy' => [
                    'min_percentage' => (float) PlatformPolicySetting::value('first_time_discount_min_percentage', 5),
                    'max_percentage' => (float) PlatformPolicySetting::value('first_time_discount_max_percentage', 50),
                    'default_percentage_cap' => (float) PlatformPolicySetting::value('first_time_discount_default_percentage_cap', 500.0),
                    'min_flat_amount' => (float) PlatformPolicySetting::value('first_time_discount_min_flat_amount', 1.0),
                    'max_flat_amount' => (float) PlatformPolicySetting::value('first_time_discount_max_flat_amount', 1000.0),
                    'default_flat_cap' => (float) PlatformPolicySetting::value('first_time_discount_default_flat_cap', 1000.0),
                    'platform_max_cap' => (float) PlatformPolicySetting::value('first_time_discount_platform_max_cap', 5000.0),
                ],
            ],
        ]);
    }

    /**
     * List all offers belonging to this salon.
     */
    public function index(string $salon_id, Request $request): JsonResponse
    {
        if ($authError = $this->authorizeSalonAdmin($salon_id, $request)) {
            return $authError;
        }

        $query = FirstTimeOffer::with(['serviceTemplates.category'])
            ->withCount('redemptions')
            ->where('salon_id', $salon_id);

        if ($request->filled('status')) {
            $statusFilter = strtolower($request->query('status'));
            if ($statusFilter === 'active') {
                $query->where('is_active', true);
            } elseif ($statusFilter === 'inactive') {
                $query->where('is_active', false);
            }
        }

        $offers = $query->orderBy('created_at', 'desc')->get();

        $mapped = $offers->map(function (FirstTimeOffer $offer) {
            return array_merge($offer->toArray(), [
                'status_label' => self::computeOfferStatus($offer),
                'is_valid_now' => $offer->isCurrentlyValid(),
                'is_limit_reached' => $offer->isRedemptionLimitReached(),
            ]);
        });

        return response()->json([
            'success' => true,
            'data' => $mapped,
        ]);
    }

    /**
     * Show a single offer belonging to this salon.
     */
    public function show(string $salon_id, string $id, Request $request): JsonResponse
    {
        if ($authError = $this->authorizeSalonAdmin($salon_id, $request)) {
            return $authError;
        }

        $offer = FirstTimeOffer::with(['serviceTemplates.category'])
            ->withCount('redemptions')
            ->where('salon_id', $salon_id)
            ->find($id);

        if (! $offer) {
            // Also explicitly check if offer exists under another salon or superadmin
            $existing = FirstTimeOffer::find($id);
            if ($existing) {
                return response()->json([
                    'success' => false,
                    'message' => 'Unauthorized. This offer does not belong to your salon.',
                ], 403);
            }

            return response()->json([
                'success' => false,
                'message' => 'Offer not found.',
            ], 404);
        }

        return response()->json([
            'success' => true,
            'data' => array_merge($offer->toArray(), [
                'status_label' => self::computeOfferStatus($offer),
                'is_valid_now' => $offer->isCurrentlyValid(),
                'is_limit_reached' => $offer->isRedemptionLimitReached(),
            ]),
        ]);
    }

    /**
     * Create a new offer for this salon.
     */
    public function store(string $salon_id, Request $request): JsonResponse
    {
        if ($authError = $this->authorizeSalonAdmin($salon_id, $request)) {
            return $authError;
        }

        if ($request->has('flat_booking_cap') && ! $request->filled('max_discount_cap')) {
            $request->merge(['max_discount_cap' => $request->input('flat_booking_cap')]);
        }
        if ($request->has('min_total_subtotal') && ! $request->filled('min_total_booking_subtotal')) {
            $request->merge(['min_total_booking_subtotal' => $request->input('min_total_subtotal')]);
        }

        $rules = FirstTimeOffer::validationRules($request->all(), true);
        $validator = Validator::make($request->all(), $rules);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed.',
                'errors' => $validator->errors(),
            ], 422);
        }

        // Validate that chosen service templates are available in this salon
        $templateIds = array_values(array_unique($request->input('service_template_ids', [])));
        $availableTemplates = Service::where('salon_id', $salon_id)
            ->whereIn('template_id', $templateIds)
            ->pluck('template_id')
            ->toArray();

        $invalidTemplates = array_diff($templateIds, $availableTemplates);
        if (! empty($invalidTemplates)) {
            return response()->json([
                'success' => false,
                'message' => 'One or more selected services are not offered by your salon.',
                'errors' => ['service_template_ids' => ['Selected services must belong to this salon.']],
            ], 422);
        }

        $offer = DB::transaction(function () use ($salon_id, $request, $templateIds) {
            $offerData = $request->only([
                'name',
                'description',
                'scope',
                'discount_type',
                'discount_value',
                'max_discount_cap',
                'min_service_price',
                'min_eligible_subtotal',
                'min_total_booking_subtotal',
                'is_active',
                'starts_at',
                'ends_at',
                'max_redemptions',
            ]);

            $offerData['salon_id'] = $salon_id;

            // Default caps if missing
            if (! isset($offerData['max_discount_cap']) || $offerData['max_discount_cap'] === null) {
                if ($offerData['discount_type'] === FirstTimeOffer::TYPE_PERCENTAGE) {
                    $offerData['max_discount_cap'] = (float) PlatformPolicySetting::value('first_time_discount_default_percentage_cap', 500.0);
                } elseif ($offerData['discount_type'] === FirstTimeOffer::TYPE_FLAT) {
                    $offerData['max_discount_cap'] = (float) PlatformPolicySetting::value('first_time_discount_default_flat_cap', 1000.0);
                }
            }

            $offer = FirstTimeOffer::create($offerData);

            // Attach explicitly selected service templates
            $offer->serviceTemplates()->attach($templateIds);

            // Relate salon in participating salons pivot as well
            $offer->participatingSalons()->attach([$salon_id]);

            return $offer;
        });

        return response()->json([
            'success' => true,
            'message' => 'Offer created successfully.',
            'data' => array_merge($offer->fresh(['serviceTemplates.category'])->toArray(), [
                'status_label' => self::computeOfferStatus($offer),
            ]),
        ], 201);
    }

    /**
     * Update an existing salon offer.
     */
    public function update(string $salon_id, string $id, Request $request): JsonResponse
    {
        if ($authError = $this->authorizeSalonAdmin($salon_id, $request)) {
            return $authError;
        }

        $offer = FirstTimeOffer::find($id);
        if (! $offer) {
            return response()->json([
                'success' => false,
                'message' => 'Offer not found.',
            ], 404);
        }

        // Prevent modifying platform offers or another salon's offer
        if ($offer->salon_id !== $salon_id) {
            return response()->json([
                'success' => false,
                'message' => 'Unauthorized. You cannot modify an offer that does not belong to your salon.',
            ], 403);
        }

        if ($request->has('flat_booking_cap') && ! $request->filled('max_discount_cap')) {
            $request->merge(['max_discount_cap' => $request->input('flat_booking_cap')]);
        }
        if ($request->has('min_total_subtotal') && ! $request->filled('min_total_booking_subtotal')) {
            $request->merge(['min_total_booking_subtotal' => $request->input('min_total_subtotal')]);
        }

        $rules = FirstTimeOffer::validationRules($request->all(), true);
        $validator = Validator::make($request->all(), $rules);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed.',
                'errors' => $validator->errors(),
            ], 422);
        }

        // Validate service templates belong to this salon
        $templateIds = array_values(array_unique($request->input('service_template_ids', [])));
        $availableTemplates = Service::where('salon_id', $salon_id)
            ->whereIn('template_id', $templateIds)
            ->pluck('template_id')
            ->toArray();

        $invalidTemplates = array_diff($templateIds, $availableTemplates);
        if (! empty($invalidTemplates)) {
            return response()->json([
                'success' => false,
                'message' => 'One or more selected services are not offered by your salon.',
                'errors' => ['service_template_ids' => ['Selected services must belong to this salon.']],
            ], 422);
        }

        DB::transaction(function () use ($offer, $request, $templateIds) {
            $offerData = $request->only([
                'name',
                'description',
                'scope',
                'discount_type',
                'discount_value',
                'max_discount_cap',
                'min_service_price',
                'min_eligible_subtotal',
                'min_total_booking_subtotal',
                'is_active',
                'starts_at',
                'ends_at',
                'max_redemptions',
            ]);

            $offer->update($offerData);
            $offer->serviceTemplates()->sync($templateIds);
        });

        return response()->json([
            'success' => true,
            'message' => 'Offer updated successfully.',
            'data' => array_merge($offer->fresh(['serviceTemplates.category'])->toArray(), [
                'status_label' => self::computeOfferStatus($offer),
            ]),
        ]);
    }

    /**
     * Toggle active status of a salon offer.
     */
    public function toggleActive(string $salon_id, string $id, Request $request): JsonResponse
    {
        if ($authError = $this->authorizeSalonAdmin($salon_id, $request)) {
            return $authError;
        }

        $offer = FirstTimeOffer::find($id);
        if (! $offer) {
            return response()->json([
                'success' => false,
                'message' => 'Offer not found.',
            ], 404);
        }

        if ($offer->salon_id !== $salon_id) {
            return response()->json([
                'success' => false,
                'message' => 'Unauthorized. You cannot modify an offer that does not belong to your salon.',
            ], 403);
        }

        $targetActive = $request->has('is_active')
            ? filter_var($request->input('is_active'), FILTER_VALIDATE_BOOLEAN)
            : ! $offer->is_active;

        if ($targetActive) {
            if ($offer->serviceTemplates()->count() === 0) {
                return response()->json([
                    'success' => false,
                    'message' => 'Cannot activate an incomplete offer. At least one eligible service must be selected.',
                ], 422);
            }
        }

        $offer->is_active = $targetActive;
        $offer->save();

        return response()->json([
            'success' => true,
            'message' => $targetActive ? 'Offer activated successfully.' : 'Offer deactivated successfully.',
            'data' => [
                'id' => $offer->id,
                'is_active' => $offer->is_active,
                'status_label' => self::computeOfferStatus($offer),
                'is_valid_now' => $offer->isCurrentlyValid(),
            ],
        ]);
    }

    /**
     * Soft delete an offer belonging to this salon.
     */
    public function destroy(string $salon_id, string $id, Request $request): JsonResponse
    {
        if ($authError = $this->authorizeSalonAdmin($salon_id, $request)) {
            return $authError;
        }

        $offer = FirstTimeOffer::find($id);
        if (! $offer) {
            return response()->json([
                'success' => false,
                'message' => 'Offer not found.',
            ], 404);
        }

        if ($offer->salon_id !== $salon_id) {
            return response()->json([
                'success' => false,
                'message' => 'Unauthorized. You cannot delete an offer that does not belong to your salon.',
            ], 403);
        }

        $offer->delete();

        return response()->json([
            'success' => true,
            'message' => 'Offer deleted successfully.',
        ]);
    }
}
