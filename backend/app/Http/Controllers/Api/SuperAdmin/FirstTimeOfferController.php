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

/**
 * First-time customer offers, as SuperAdmin sees them.
 *
 * Offers are a salon's own: each salon creates them for itself from the
 * Partner App. SuperAdmin oversees them here — every salon's offers, named by
 * the salon that made them — and can pause or remove one that breaks the
 * rules, but does not create or edit them. The platform-wide offers this page
 * used to create are retired and can no longer be switched back on.
 */
class FirstTimeOfferController extends Controller
{
    private const SALON_ONLY = 'First-time offers are created by salons for their own salon, from the Partner App. SuperAdmin can pause or remove an offer, but not create or edit one.';

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

        $query = FirstTimeOffer::with('salon:id,name')
            ->withCount(['serviceTemplates', 'participatingSalons', 'redemptions']);

        if ($request->filled('salon_id')) {
            $request->query('salon_id') === 'platform'
                ? $query->whereNull('salon_id')
                : $query->where('salon_id', $request->query('salon_id'));
        }

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
                // Which salon made it; null for the retired platform offers.
                'created_by_salon' => $offer->salon ? ['id' => $offer->salon->id, 'name' => $offer->salon->name] : null,
                'is_retired_platform_offer' => $offer->salon_id === null,
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
            'salon:id,name',
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

        return response()->json(['success' => false, 'message' => self::SALON_ONLY], 403);
    }

    /**
     * Update an existing offer.
     */
    public function update(Request $request, string $id): JsonResponse
    {
        if ($authError = $this->authorizeAdmin($request)) {
            return $authError;
        }

        return response()->json(['success' => false, 'message' => self::SALON_ONLY], 403);
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

        if ($targetActive && $offer->salon_id === null) {
            return response()->json([
                'success' => false,
                'message' => 'Platform-wide offers are retired. Offers now belong to salons, which create them in the Partner App.',
            ], 422);
        }

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
