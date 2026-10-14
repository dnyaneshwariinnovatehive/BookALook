<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\FirstTimeOffer;
use App\Models\PlatformPolicySetting;
use App\Models\Salon;
use App\Models\ServiceCategory;
use App\Models\ServiceTemplate;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

class FirstTimeOfferController extends Controller
{
    /**
     * Authorize that the current authenticated user has administrator privileges.
     */
    private function authorizeAdmin(Request $request): ?JsonResponse
    {
        $user = $request->user();

        if (! $user || ! in_array($user->role, ['superadmin', 'admin'], true)) {
            return response()->json([
                'success' => false,
                'message' => 'Unauthorized. Administrator access required.',
            ], 403);
        }

        return null;
    }

    /**
     * List all first-time customer offers with counts and computed status.
     */
    public function index(Request $request): JsonResponse
    {
        if ($authError = $this->authorizeAdmin($request)) {
            return $authError;
        }

        $query = FirstTimeOffer::withCount(['serviceTemplates', 'participatingSalons', 'redemptions']);

        if ($request->filled('scope')) {
            $query->where('scope', $request->query('scope'));
        }

        if ($request->filled('discount_type')) {
            $query->where('discount_type', $request->query('discount_type'));
        }

        if ($request->has('is_active') && $request->query('is_active') !== '') {
            $query->where('is_active', filter_var($request->query('is_active'), FILTER_VALIDATE_BOOLEAN));
        }

        $offers = $query->orderBy('created_at', 'desc')->get();

        $mapped = $offers->map(function (FirstTimeOffer $offer) {
            return array_merge($offer->toArray(), [
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
     * Retrieve available service templates and salons for configuration selectors.
     */
    public function options(Request $request): JsonResponse
    {
        if ($authError = $this->authorizeAdmin($request)) {
            return $authError;
        }

        $categories = ServiceCategory::with(['templates' => function ($query) {
            $query->where('is_active', true)->orderBy('name', 'asc');
        }])
            ->where('is_active', true)
            ->orderBy('name', 'asc')
            ->get(['id', 'name']);

        $salons = Salon::with('city:id,name')
            ->where('status', 'active')
            ->orderBy('name', 'asc')
            ->get(['id', 'name', 'city_id', 'address']);

        return response()->json([
            'success' => true,
            'data' => [
                'categories' => $categories,
                'salons' => $salons->map(function ($salon) {
                    return [
                        'id' => $salon->id,
                        'name' => $salon->name,
                        'city' => $salon->city->name ?? 'Unknown',
                        'address' => $salon->address,
                    ];
                }),
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
     * View one offer with its full configuration.
     */
    public function show(Request $request, string $id): JsonResponse
    {
        if ($authError = $this->authorizeAdmin($request)) {
            return $authError;
        }

        $offer = FirstTimeOffer::with([
            'serviceTemplates.category:id,name',
            'participatingSalons.city:id,name',
        ])
            ->withCount('redemptions')
            ->find($id);

        if (! $offer) {
            return response()->json([
                'success' => false,
                'message' => 'Offer not found',
            ], 404);
        }

        return response()->json([
            'success' => true,
            'data' => array_merge($offer->toArray(), [
                'is_valid_now' => $offer->isCurrentlyValid(),
                'is_limit_reached' => $offer->isRedemptionLimitReached(),
            ]),
        ]);
    }

    /**
     * Create a new first-time customer offer.
     */
    public function store(Request $request): JsonResponse
    {
        if ($authError = $this->authorizeAdmin($request)) {
            return $authError;
        }

        if ($request->has('flat_booking_cap') && ! $request->filled('max_discount_cap')) {
            $request->merge(['max_discount_cap' => $request->input('flat_booking_cap')]);
        }
        if ($request->has('min_total_subtotal') && ! $request->filled('min_total_booking_subtotal')) {
            $request->merge(['min_total_booking_subtotal' => $request->input('min_total_subtotal')]);
        }

        $rules = FirstTimeOffer::validationRules($request->all());
        $validator = Validator::make($request->all(), $rules);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $offer = DB::transaction(function () use ($request) {
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

            // Set default caps if not provided
            if (! isset($offerData['max_discount_cap']) || $offerData['max_discount_cap'] === null) {
                if ($offerData['discount_type'] === FirstTimeOffer::TYPE_PERCENTAGE) {
                    $offerData['max_discount_cap'] = (float) PlatformPolicySetting::value('first_time_discount_default_percentage_cap', 500.0);
                } elseif ($offerData['discount_type'] === FirstTimeOffer::TYPE_FLAT) {
                    $offerData['max_discount_cap'] = (float) PlatformPolicySetting::value('first_time_discount_default_flat_cap', 1000.0);
                }
            }

            $offer = FirstTimeOffer::create($offerData);

            // Attach explicitly selected service templates (unique)
            $templateIds = array_values(array_unique($request->input('service_template_ids', [])));
            $offer->serviceTemplates()->attach($templateIds);

            // Attach participating salons (if scope is new_to_salon or explicitly provided)
            if ($request->has('salon_ids') && is_array($request->input('salon_ids'))) {
                $salonIds = array_values(array_unique($request->input('salon_ids')));
                if (! empty($salonIds)) {
                    $offer->participatingSalons()->attach($salonIds);
                }
            }

            return $offer;
        });

        return response()->json([
            'success' => true,
            'message' => 'First-time customer offer created successfully.',
            'data' => $offer->fresh(['serviceTemplates', 'participatingSalons']),
        ], 201);
    }

    /**
     * Update an existing offer.
     */
    public function update(Request $request, string $id): JsonResponse
    {
        if ($authError = $this->authorizeAdmin($request)) {
            return $authError;
        }

        $offer = FirstTimeOffer::find($id);

        if (! $offer) {
            return response()->json([
                'success' => false,
                'message' => 'Offer not found',
            ], 404);
        }

        if ($request->has('flat_booking_cap') && ! $request->filled('max_discount_cap')) {
            $request->merge(['max_discount_cap' => $request->input('flat_booking_cap')]);
        }
        if ($request->has('min_total_subtotal') && ! $request->filled('min_total_booking_subtotal')) {
            $request->merge(['min_total_booking_subtotal' => $request->input('min_total_subtotal')]);
        }

        $rules = FirstTimeOffer::validationRules($request->all());
        $validator = Validator::make($request->all(), $rules);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        DB::transaction(function () use ($offer, $request) {
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

            // Sync service templates
            $templateIds = array_values(array_unique($request->input('service_template_ids', [])));
            $offer->serviceTemplates()->sync($templateIds);

            // Sync participating salons
            $salonIds = $request->has('salon_ids') && is_array($request->input('salon_ids'))
                ? array_values(array_unique($request->input('salon_ids')))
                : [];
            $offer->participatingSalons()->sync($salonIds);
        });

        return response()->json([
            'success' => true,
            'message' => 'Offer updated successfully.',
            'data' => $offer->fresh(['serviceTemplates', 'participatingSalons']),
        ]);
    }

    /**
     * Toggle active status of an offer with completeness validation.
     */
    public function toggleActive(Request $request, string $id): JsonResponse
    {
        if ($authError = $this->authorizeAdmin($request)) {
            return $authError;
        }

        $offer = FirstTimeOffer::find($id);

        if (! $offer) {
            return response()->json([
                'success' => false,
                'message' => 'Offer not found',
            ], 404);
        }

        $targetActive = $request->has('is_active')
            ? filter_var($request->input('is_active'), FILTER_VALIDATE_BOOLEAN)
            : ! $offer->is_active;

        if ($targetActive) {
            // Completeness check before activation
            if ($offer->serviceTemplates()->count() === 0) {
                return response()->json([
                    'success' => false,
                    'message' => 'Cannot activate an incomplete offer. At least one eligible service template must be selected.',
                ], 422);
            }

            if ($offer->scope === FirstTimeOffer::SCOPE_NEW_TO_SALON && $offer->participatingSalons()->count() === 0) {
                return response()->json([
                    'success' => false,
                    'message' => 'Cannot activate a salon-specific offer without participating salons.',
                ], 422);
            }
        }

        $offer->is_active = $targetActive;
        $offer->save();

        return response()->json([
            'success' => true,
            'message' => $targetActive ? 'Offer activated successfully.' : 'Offer paused successfully.',
            'data' => [
                'id' => $offer->id,
                'is_active' => $offer->is_active,
                'is_valid_now' => $offer->isCurrentlyValid(),
            ],
        ]);
    }

    /**
     * Soft delete an offer.
     */
    public function destroy(Request $request, string $id): JsonResponse
    {
        if ($authError = $this->authorizeAdmin($request)) {
            return $authError;
        }

        $offer = FirstTimeOffer::find($id);

        if (! $offer) {
            return response()->json([
                'success' => false,
                'message' => 'Offer not found',
            ], 404);
        }

        $offer->delete();

        return response()->json([
            'success' => true,
            'message' => 'Offer deleted successfully.',
        ]);
    }
}
