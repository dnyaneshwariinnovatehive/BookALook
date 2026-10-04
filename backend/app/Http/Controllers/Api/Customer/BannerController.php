<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\Banner;
use App\Models\Combo;
use App\Models\Salon;
use App\Models\ServiceCategory;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;

class BannerController extends Controller
{
    /**
     * Display a listing of active banners for the customer app.
     */
    public function index(Request $request)
    {
        $targetCityId = $request->input('target_city_id');
        $targetSubAreaId = $request->input('target_sub_area_id');
        $targetSalonId = $request->input('target_salon_id');

        $query = Banner::where('is_active', true)
            ->whereDate('start_date', '<=', now())
            ->whereDate('end_date', '>=', now())
            ->where(function ($q) use ($targetCityId, $targetSubAreaId, $targetSalonId) {
                // Always include platform-wide banners
                $q->where('target_scope', 'platform');
                
                // City banners
                if ($targetCityId) {
                    $q->orWhere(function ($subQ) use ($targetCityId) {
                        $subQ->where('target_scope', 'city')
                             ->where('target_city_id', $targetCityId);
                    });
                }

                // Sub-area banners
                if ($targetSubAreaId) {
                    $q->orWhere(function ($subQ) use ($targetSubAreaId) {
                        $subQ->where('target_scope', 'sub_area')
                             ->where('target_sub_area_id', $targetSubAreaId);
                    });
                }
                
                // Salon banners
                if ($targetSalonId) {
                    $q->orWhere(function ($subQ) use ($targetSalonId) {
                        $subQ->where('target_scope', 'salon')
                             ->where('target_salon_id', $targetSalonId);
                    });
                }
            });

        // Priority ascending, then start_date descending
        $banners = $query->orderBy('priority', 'asc')->orderBy('start_date', 'desc')->get();

        $resolvedBanners = [];

        foreach ($banners as $banner) {
            if ($banner->banner_type === 'static' || $banner->banner_type === 'seasonal') {
                $resolvedBanners[] = $banner;
                continue;
            }

            // For dynamic banners, we check if they have content. If not, and auto_hide is true, we skip them.
            $hasContent = $this->resolveDynamicBanner($banner);
            $autoHide = $banner->config['auto_hide'] ?? true; // default to auto hide

            if ($hasContent || !$autoHide) {
                // We add some fallback styling or auto-generated fields if it lacks an image
                if (empty($banner->image_url)) {
                    // Fallback to a placeholder or gradient based on type
                    $banner->image_url = 'https://via.placeholder.com/800x320/F3EBFE/6B46C1?text=' . urlencode(str_replace('_', ' ', strtoupper($banner->banner_type)));
                }
                
                // We can also attach deep links if action_url is empty
                if (empty($banner->action_url)) {
                    if ($banner->banner_type === 'combo_discount' || $banner->banner_type === 'specific_combo') {
                        $banner->action_url = 'bookalook://combos';
                    } elseif ($banner->banner_type === 'new_arrivals') {
                        $banner->action_url = 'bookalook://salons?sort=newest';
                    } elseif ($banner->banner_type === 'category_spotlight' && !empty($banner->config['category_id'])) {
                        $banner->action_url = 'bookalook://category/' . $banner->config['category_id'];
                    }
                }

                $resolvedBanners[] = $banner;
            }
        }

        return response()->json(array_values($resolvedBanners));
    }

    /**
     * Returns true if the dynamic banner finds matching salons/combos in its scope.
     * Caches the result per banner for 15 minutes since these queries are heavy.
     */
    private function resolveDynamicBanner(Banner $banner): bool
    {
        $cacheKey = "banner_resolution_{$banner->id}";

        return Cache::remember($cacheKey, 60 * 15, function () use ($banner) {
            $config = $banner->config ?? [];
            $scope = $banner->target_scope;
            $cityId = $banner->target_city_id;
            $subAreaId = $banner->target_sub_area_id;

            $salonQuery = Salon::query()->where('status', 'approved');
            if ($scope === 'city' && $cityId) {
                $salonQuery->where('city_id', $cityId);
            } elseif ($scope === 'sub_area' && $subAreaId) {
                $salonQuery->where('sub_area_id', $subAreaId);
            } elseif ($scope === 'salon' && $banner->target_salon_id) {
                $salonQuery->where('id', $banner->target_salon_id);
            }
            $salonIds = $salonQuery->pluck('id');

            if ($salonIds->isEmpty()) {
                return false;
            }

            if ($banner->banner_type === 'combo_discount') {
                $minPct = $config['min_discount_pct'] ?? 20;
                $combos = Combo::where('is_active', true)->whereIn('salon_id', $salonIds)->with('services')->get();
                foreach ($combos as $combo) {
                    $originalTotal = $combo->services->sum(fn($s) => (float) $s->price);
                    $comboTotal = $combo->services->sum(fn($s) => (float) $s->pivot->combo_special_price);
                    if ($originalTotal > 0) {
                        $discount = (($originalTotal - $comboTotal) / $originalTotal) * 100;
                        if ($discount >= $minPct) return true;
                    }
                }
                return false;
            }

            if ($banner->banner_type === 'specific_combo') {
                $templateIds = $config['service_template_ids'] ?? [];
                if (empty($templateIds)) return false;

                $combos = Combo::where('is_active', true)->whereIn('salon_id', $salonIds)->with('services')->get();
                foreach ($combos as $combo) {
                    $comboTemplateIds = $combo->services->pluck('template_id')->toArray();
                    if (count(array_intersect($templateIds, $comboTemplateIds)) === count($templateIds)) {
                        return true;
                    }
                }
                return false;
            }

            if ($banner->banner_type === 'new_arrivals') {
                $windowDays = $config['window_days'] ?? 7;
                $cutoff = Carbon::now()->subDays($windowDays);
                return Salon::whereIn('id', $salonIds)->where('created_at', '>=', $cutoff)->exists();
            }

            if ($banner->banner_type === 'category_spotlight') {
                $categoryId = $config['category_id'] ?? null;
                if (!$categoryId) return false;

                return Salon::whereIn('id', $salonIds)
                    ->whereHas('services', function ($q) use ($categoryId) {
                        $q->where('is_active', true)
                          ->whereHas('template', fn($tq) => $tq->where('category_id', $categoryId));
                    })->exists();
            }

            return false;
        });
    }
}
