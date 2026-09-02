<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\Banner;
use Illuminate\Http\Request;

class BannerController extends Controller
{
    /**
     * Display a listing of active banners for the customer app.
     */
    public function index(Request $request)
    {
        $targetCityId = $request->input('target_city_id');
        $targetSalonId = $request->input('target_salon_id');

        $query = Banner::where('is_active', true)
            ->whereDate('start_date', '<=', now())
            ->whereDate('end_date', '>=', now())
            ->where(function ($q) use ($targetCityId, $targetSalonId) {
                // Always include platform-wide banners
                $q->where('target_scope', 'platform');
                
                // If a city is specified, include city-specific banners for that city
                if ($targetCityId) {
                    $q->orWhere(function ($subQ) use ($targetCityId) {
                        $subQ->where('target_scope', 'city')
                             ->where('target_city_id', $targetCityId);
                    });
                }
                
                // If a salon ID is specified, include salon-specific banners for that salon
                if ($targetSalonId) {
                    $q->orWhere(function ($subQ) use ($targetSalonId) {
                        $subQ->where('target_scope', 'salon')
                             ->where('target_salon_id', $targetSalonId);
                    });
                }
            });

        // Order by start_date descending (newest campaigns first)
        $banners = $query->orderBy('start_date', 'desc')->get();

        return response()->json($banners);
    }
}
