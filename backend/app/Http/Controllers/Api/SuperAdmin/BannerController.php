<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\Banner;
use App\Models\Combo;
use App\Models\Salon;
use App\Models\Service;
use App\Models\ServiceCategory;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class BannerController extends Controller
{
    public function index(Request $request)
    {
        $query = Banner::query()->with(['city', 'salon', 'subArea']);

        if ($request->has('status')) {
            $status = $request->input('status');
            $now = now()->toDateString();
            if ($status === 'active') {
                $query->where('is_active', true)
                      ->where('start_date', '<=', $now)
                      ->where('end_date', '>=', $now);
            } elseif ($status === 'inactive') {
                $query->where('is_active', false);
            } elseif ($status === 'expired') {
                $query->where('end_date', '<', $now);
            }
        }

        if ($request->has('target_scope')) {
            $query->where('target_scope', $request->input('target_scope'));
        }

        if ($request->has('target_city_id')) {
            $query->where('target_city_id', $request->input('target_city_id'));
        }

        if ($request->has('banner_type')) {
            $query->where('banner_type', $request->input('banner_type'));
        }

        $perPage = $request->input('per_page', 15);
        $banners = $query->orderBy('priority')->orderBy('start_date', 'desc')->paginate($perPage);

        return response()->json($banners);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'title'              => 'required|string|max:150',
            'banner_type'        => 'required|in:' . implode(',', Banner::TYPES),
            'config'             => 'nullable|array',
            'image_url'          => 'nullable|url|max:255',
            'action_url'         => 'nullable|url|max:255',
            'target_scope'       => 'required|in:platform,city,salon,sub_area',
            'target_city_id'     => 'nullable|exists:cities,id',
            'target_salon_id'    => 'nullable|uuid',
            'target_sub_area_id' => 'nullable|exists:sub_areas,id',
            'start_date'         => 'required|date',
            'end_date'           => 'required|date|after:start_date',
            'is_active'          => 'boolean',
            'priority'           => 'nullable|integer|min:0',
        ]);

        // Static banners require an image
        if ($validated['banner_type'] === 'static' && empty($validated['image_url'])) {
            return response()->json(['message' => 'Static banners require an image.'], 422);
        }

        $banner = Banner::create($validated);

        return response()->json(['message' => 'Banner created successfully', 'banner' => $banner->load(['city', 'salon', 'subArea'])], 201);
    }

    public function update(Request $request, $id)
    {
        $banner = Banner::findOrFail($id);

        $validated = $request->validate([
            'title'              => 'sometimes|string|max:150',
            'banner_type'        => 'sometimes|in:' . implode(',', Banner::TYPES),
            'config'             => 'nullable|array',
            'image_url'          => 'nullable|url|max:255',
            'action_url'         => 'nullable|url|max:255',
            'target_scope'       => 'sometimes|in:platform,city,salon,sub_area',
            'target_city_id'     => 'nullable|exists:cities,id',
            'target_salon_id'    => 'nullable|uuid',
            'target_sub_area_id' => 'nullable|exists:sub_areas,id',
            'start_date'         => 'sometimes|required|date',
            'end_date'           => 'sometimes|required|date|after:start_date',
            'is_active'          => 'boolean',
            'priority'           => 'nullable|integer|min:0',
        ]);

        $banner->update($validated);

        return response()->json(['message' => 'Banner updated successfully', 'banner' => $banner->load(['city', 'salon', 'subArea'])]);
    }

    public function destroy($id)
    {
        $banner = Banner::findOrFail($id);
        $banner->delete();

        return response()->json(['message' => 'Banner deleted successfully']);
    }

    /**
     * Track a banner impression or click.
     */
    public function track(Request $request, $id)
    {
        $request->validate(['event' => 'required|in:impression,click']);
        $column = $request->input('event') === 'click' ? 'clicks' : 'impressions';
        Banner::where('id', $id)->increment($column);

        return response()->json(['ok' => true]);
    }

    /* ─── Live Preview ────────────────────────────────────────────────
     *
     * Given a banner_type + config + targeting, return the real data the
     * customer app would see. SuperAdmin uses this to preview before saving.
     */
    public function preview(Request $request)
    {
        $request->validate([
            'banner_type'        => 'required|in:' . implode(',', Banner::TYPES),
            'config'             => 'nullable|array',
            'target_scope'       => 'required|in:platform,city,salon,sub_area',
            'target_city_id'     => 'nullable|exists:cities,id',
            'target_sub_area_id' => 'nullable|exists:sub_areas,id',
            'target_salon_id'    => 'nullable|uuid',
        ]);

        $type     = $request->input('banner_type');
        $config   = $request->input('config', []);
        $scope    = $request->input('target_scope');
        $cityId   = $request->input('target_city_id');
        $subAreaId = $request->input('target_sub_area_id');
        $salonId  = $request->input('target_salon_id');

        $result = match ($type) {
            'combo_discount'     => $this->previewComboDiscount($config, $scope, $cityId, $subAreaId),
            'specific_combo'     => $this->previewSpecificCombo($config, $scope, $cityId, $subAreaId),
            'new_arrivals'       => $this->previewNewArrivals($config, $scope, $cityId, $subAreaId),
            'category_spotlight' => $this->previewCategorySpotlight($config, $scope, $cityId, $subAreaId),
            'seasonal'           => ['salons' => [], 'summary' => 'Seasonal banners show a static themed image.'],
            'static'             => ['salons' => [], 'summary' => 'Static banners show an uploaded image.'],
        };

        return response()->json(['success' => true, ...$result]);
    }

    /* ─── Preview helpers ─────────────────────────────── */

    private function scopedSalons(string $scope, ?string $cityId, ?string $subAreaId)
    {
        $query = Salon::query()->where('status', 'approved');

        if ($scope === 'city' && $cityId) {
            $query->where('city_id', $cityId);
        } elseif ($scope === 'sub_area' && $subAreaId) {
            $query->where('sub_area_id', $subAreaId);
        }

        return $query;
    }

    private function previewComboDiscount(array $config, string $scope, ?string $cityId, ?string $subAreaId): array
    {
        $minPct = $config['min_discount_pct'] ?? 20;

        // Get all active combos from scoped salons with their services
        $salonQuery = $this->scopedSalons($scope, $cityId, $subAreaId);
        $salonIds = $salonQuery->pluck('id');

        $combos = Combo::where('is_active', true)
            ->whereIn('salon_id', $salonIds)
            ->with(['services', 'salon:id,name,city_id'])
            ->get();

        $qualifying = $combos->filter(function ($combo) use ($minPct) {
            $originalTotal = $combo->services->sum(function ($s) {
                return (float) $s->price;
            });
            $comboTotal = $combo->services->sum(function ($s) {
                return (float) $s->pivot->combo_special_price;
            });

            if ($originalTotal <= 0) return false;

            $discount = (($originalTotal - $comboTotal) / $originalTotal) * 100;
            return $discount >= $minPct;
        });

        $salons = $qualifying->pluck('salon')->unique('id')->values()->map(fn($s) => [
            'id'   => $s->id,
            'name' => $s->name,
        ]);

        return [
            'salons'  => $salons,
            'combos'  => $qualifying->values()->map(fn($c) => [
                'id'         => $c->id,
                'name'       => $c->name,
                'salon_name' => $c->salon->name ?? '',
                'services'   => $c->services->map(fn($s) => [
                    'name'          => $s->name ?? ($s->template->name ?? ''),
                    'original_price' => (float) $s->price,
                    'combo_price'    => (float) $s->pivot->combo_special_price,
                ]),
            ]),
            'summary' => $qualifying->count() . ' combos with ' . $minPct . '%+ discount across ' . $salons->count() . ' salons',
        ];
    }

    private function previewSpecificCombo(array $config, string $scope, ?string $cityId, ?string $subAreaId): array
    {
        $templateIds = $config['service_template_ids'] ?? [];

        if (empty($templateIds)) {
            return ['salons' => [], 'combos' => [], 'summary' => 'Select service templates to preview.'];
        }

        $salonIds = $this->scopedSalons($scope, $cityId, $subAreaId)->pluck('id');

        // Find combos that contain ALL specified service templates
        $combos = Combo::where('is_active', true)
            ->whereIn('salon_id', $salonIds)
            ->with(['services.template', 'salon:id,name'])
            ->get()
            ->filter(function ($combo) use ($templateIds) {
                $comboTemplateIds = $combo->services->pluck('template_id')->toArray();
                return count(array_intersect($templateIds, $comboTemplateIds)) === count($templateIds);
            });

        $salons = $combos->pluck('salon')->unique('id')->values()->map(fn($s) => [
            'id'   => $s->id,
            'name' => $s->name,
        ]);

        return [
            'salons'  => $salons,
            'combos'  => $combos->values()->map(fn($c) => [
                'id'         => $c->id,
                'name'       => $c->name,
                'salon_name' => $c->salon->name ?? '',
            ]),
            'summary' => $combos->count() . ' matching combos across ' . $salons->count() . ' salons',
        ];
    }

    private function previewNewArrivals(array $config, string $scope, ?string $cityId, ?string $subAreaId): array
    {
        $windowDays = $config['window_days'] ?? 7;
        $cutoff = Carbon::now()->subDays($windowDays);

        $salons = $this->scopedSalons($scope, $cityId, $subAreaId)
            ->where('created_at', '>=', $cutoff)
            ->select('id', 'name', 'created_at')
            ->orderBy('created_at', 'desc')
            ->limit(50)
            ->get()
            ->map(fn($s) => [
                'id'         => $s->id,
                'name'       => $s->name,
                'listed_at'  => $s->created_at->diffForHumans(),
            ]);

        return [
            'salons'  => $salons,
            'summary' => $salons->count() . ' new salons in the last ' . $windowDays . ' days',
        ];
    }

    private function previewCategorySpotlight(array $config, string $scope, ?string $cityId, ?string $subAreaId): array
    {
        $categoryId = $config['category_id'] ?? null;

        if (!$categoryId) {
            return ['salons' => [], 'summary' => 'Select a category to preview.'];
        }

        $category = ServiceCategory::find($categoryId);
        if (!$category) {
            return ['salons' => [], 'summary' => 'Category not found.'];
        }

        $salons = $this->scopedSalons($scope, $cityId, $subAreaId)
            ->whereHas('services', function ($q) use ($categoryId) {
                $q->where('is_active', true)
                  ->whereHas('template', fn($tq) => $tq->where('category_id', $categoryId));
            })
            ->select('id', 'name')
            ->limit(50)
            ->get()
            ->map(fn($s) => ['id' => $s->id, 'name' => $s->name]);

        return [
            'salons'  => $salons,
            'category_name' => $category->name,
            'summary' => $salons->count() . ' salons offer ' . $category->name . ' services',
        ];
    }
}
