<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Banner;

class BannerController extends Controller
{
    public function index(Request $request)
    {
        $query = Banner::query();

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

        $perPage = $request->input('per_page', 15);
        $banners = $query->orderBy('start_date', 'desc')->paginate($perPage);
        
        return response()->json($banners);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'title' => 'required|string|max:150',
            'image_url' => 'required|url|max:255',
            'action_url' => 'nullable|url|max:255',
            'target_scope' => 'required|in:platform,city,salon',
            'target_city_id' => 'nullable|exists:cities,id|required_if:target_scope,city',
            'target_salon_id' => 'nullable|uuid|required_if:target_scope,salon',
            'start_date' => 'required|date',
            'end_date' => 'required|date|after_or_equal:start_date',
            'is_active' => 'boolean',
        ]);

        $banner = Banner::create($validated);

        return response()->json(['message' => 'Banner created successfully', 'banner' => $banner], 201);
    }

    public function update(Request $request, $id)
    {
        $banner = Banner::findOrFail($id);

        $validated = $request->validate([
            'title' => 'sometimes|string|max:150',
            'image_url' => 'sometimes|url|max:255',
            'action_url' => 'nullable|url|max:255',
            'target_scope' => 'sometimes|in:platform,city,salon',
            'target_city_id' => 'nullable|exists:cities,id|required_if:target_scope,city',
            'target_salon_id' => 'nullable|uuid|required_if:target_scope,salon',
            'start_date' => 'sometimes|required|date',
            'end_date' => 'sometimes|required|date|after_or_equal:start_date',
            'is_active' => 'boolean',
        ]);

        $banner->update($validated);

        return response()->json(['message' => 'Banner updated successfully', 'banner' => $banner]);
    }

    public function destroy($id)
    {
        $banner = Banner::findOrFail($id);
        $banner->delete();

        return response()->json(['message' => 'Banner deleted successfully']);
    }
}
