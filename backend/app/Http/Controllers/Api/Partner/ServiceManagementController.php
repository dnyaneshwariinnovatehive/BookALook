<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceTemplate;
use Illuminate\Support\Facades\Validator;
use App\Models\Salon;

class ServiceManagementController extends Controller
{
    public function getMasterCatalog(Request $request)
    {
        // Get all standard categories, plus any custom categories created by this salon (if salon_id provided)
        $salonId = $request->query('salon_id');

        $query = ServiceCategory::with(['templates' => function ($q) use ($salonId) {
            $q->where('is_active', true)
              ->where(function($q2) use ($salonId) {
                  $q2->where('is_custom', false)
                     ->orWhere('created_by_salon_id', $salonId);
              });
        }])
        ->where('is_active', true)
        ->where(function($q) use ($salonId) {
            $q->where('is_custom', false)
              ->orWhere('created_by_salon_id', $salonId);
        });

        return response()->json([
            'categories' => $query->get()
        ]);
    }

    public function getSalonServices($salon_id, Request $request)
    {
        // Ensure user is authorized for this salon
        $salon = Salon::findOrFail($salon_id);
        if ($salon->admin_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized for this salon'], 403);
        }

        $services = Service::with(['template.category'])
            ->where('salon_id', $salon_id)
            ->where('is_active', true)
            ->get();

        // Group by category
        $grouped = [];
        foreach ($services as $service) {
            $categoryId = $service->template->category_id;
            if (!isset($grouped[$categoryId])) {
                $grouped[$categoryId] = [
                    'category' => $service->template->category,
                    'services' => []
                ];
            }
            $grouped[$categoryId]['services'][] = $service;
        }

        return response()->json([
            'grouped_services' => array_values($grouped)
        ]);
    }

    public function addService($salon_id, Request $request)
    {
        $salon = Salon::findOrFail($salon_id);
        if ($salon->admin_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $validator = Validator::make($request->all(), [
            'is_custom' => 'required|boolean',
            'template_id' => 'required_if:is_custom,false|uuid',
            'price' => 'required|numeric|min:0',
            'description' => 'nullable|string',
            
            // Custom fields
            'category_id' => 'required_if:is_custom,true',
            'custom_category_name' => 'required_if:category_id,new_custom|string|max:80',
            'custom_template_name' => 'required_if:is_custom,true|string|max:150',
            'estimated_duration_minutes' => 'required_if:is_custom,true|integer|multiple_of:30|min:30',
            'advance_percentage' => 'nullable|numeric|min:0|max:100',
            'gender_focus' => 'nullable|string|in:Unisex,Men Only,Women Only',
            'will_refund_advance_if_cancelled' => 'nullable|boolean',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $templateId = $request->template_id;

        if ($request->is_custom) {
            $categoryId = $request->category_id;
            
            if ($categoryId === 'new_custom') {
                $category = ServiceCategory::create([
                    'name' => $request->custom_category_name,
                    'is_custom' => true,
                    'created_by_salon_id' => $salon_id,
                ]);
                $categoryId = $category->id;
            }

            $template = ServiceTemplate::create([
                'category_id' => $categoryId,
                'name' => $request->custom_template_name,
                'estimated_duration_minutes' => $request->estimated_duration_minutes,
                'is_custom' => true,
                'created_by_salon_id' => $salon_id,
            ]);
            $templateId = $template->id;
        }

        // Check if service already exists (including soft-deleted ones)
        $exists = Service::withTrashed()->where('salon_id', $salon_id)->where('template_id', $templateId)->first();
        
        if ($exists) {
            if (!$exists->trashed()) {
                return response()->json(['message' => 'Service already exists in this salon'], 400);
            }
            
            // If it was soft-deleted, restore it and update the details
            $exists->restore();
            $exists->update([
                'price' => $request->price,
                'description' => $request->description,
                'advance_percentage' => $request->advance_percentage,
                'gender_focus' => $request->gender_focus ?? 'Unisex',
                'will_refund_advance_if_cancelled' => $request->will_refund_advance_if_cancelled ?? false,
                'is_active' => true,
            ]);
            
            $service = $exists;
        } else {
            $service = Service::create([
                'salon_id' => $salon_id,
                'template_id' => $templateId,
                'price' => $request->price,
                'description' => $request->description,
                'advance_percentage' => $request->advance_percentage,
                'gender_focus' => $request->gender_focus ?? 'Unisex',
                'will_refund_advance_if_cancelled' => $request->will_refund_advance_if_cancelled ?? false,
            ]);
        }

        return response()->json([
            'message' => 'Service added successfully',
            'service' => $service->load('template.category')
        ]);
    }

    public function updateService($salon_id, $service_id, Request $request)
    {
        $salon = Salon::findOrFail($salon_id);
        if ($salon->admin_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $service = Service::where('salon_id', $salon_id)->findOrFail($service_id);

        $validator = Validator::make($request->all(), [
            'price' => 'sometimes|numeric|min:0',
            'description' => 'nullable|string',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        if ($request->has('price')) $service->price = $request->price;
        if ($request->has('description')) $service->description = $request->description;
        
        $service->save();

        return response()->json([
            'message' => 'Service updated successfully',
            'service' => $service->load('template.category')
        ]);
    }

    public function deleteService($salon_id, $service_id, Request $request)
    {
        $salon = Salon::findOrFail($salon_id);
        if ($salon->admin_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $service = Service::where('salon_id', $salon_id)->findOrFail($service_id);
        $service->delete();

        return response()->json(['message' => 'Service deleted successfully']);
    }
    public function getCombos($salon_id, Request $request)
    {
        $salon = Salon::findOrFail($salon_id);
        if ($salon->admin_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $combos = \App\Models\Combo::with('services.template.category')
            ->where('salon_id', $salon_id)
            ->where('is_active', true)
            ->get();

        return response()->json(['combos' => $combos]);
    }

    public function createCombo($salon_id, Request $request)
    {
        $salon = Salon::findOrFail($salon_id);
        if ($salon->admin_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:150',
            'advance_percentage' => 'nullable|numeric|min:0|max:100',
            'will_refund_advance_if_cancelled' => 'nullable|boolean',
            'services' => 'required|array|min:2',
            'services.*.service_id' => 'required|uuid|exists:services,id',
            'services.*.special_price' => 'required|numeric|min:0',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $combo = \App\Models\Combo::create([
            'salon_id' => $salon_id,
            'name' => $request->name,
            'advance_percentage' => $request->advance_percentage ?? 25.00,
            'will_refund_advance_if_cancelled' => $request->will_refund_advance_if_cancelled ?? false,
        ]);

        foreach ($request->services as $serviceData) {
            \App\Models\ComboService::create([
                'combo_id' => $combo->id,
                'service_id' => $serviceData['service_id'],
                'combo_special_price' => $serviceData['special_price'],
            ]);
        }

        return response()->json([
            'message' => 'Combo created successfully',
            'combo' => $combo->load('services.template')
        ]);
    }

    public function updateCombo($salon_id, $combo_id, Request $request)
    {
        $salon = Salon::findOrFail($salon_id);
        if ($salon->admin_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $combo = \App\Models\Combo::where('salon_id', $salon_id)->findOrFail($combo_id);

        $validator = Validator::make($request->all(), [
            'name' => 'sometimes|required|string|max:150',
            'advance_percentage' => 'nullable|numeric|min:0|max:100',
            'will_refund_advance_if_cancelled' => 'nullable|boolean',
            'services' => 'sometimes|required|array|min:2',
            'services.*.service_id' => 'required|uuid|exists:services,id',
            'services.*.special_price' => 'required|numeric|min:0',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        if ($request->has('name')) {
            $combo->name = $request->name;
        }
        if ($request->has('advance_percentage')) {
            $combo->advance_percentage = $request->advance_percentage;
        }
        if ($request->has('will_refund_advance_if_cancelled')) {
            $combo->will_refund_advance_if_cancelled = $request->will_refund_advance_if_cancelled;
        }
        
        $combo->save();

        if ($request->has('services')) {
            $syncData = [];
            foreach ($request->services as $serviceData) {
                $syncData[$serviceData['service_id']] = ['combo_special_price' => $serviceData['special_price']];
            }
            $combo->services()->sync($syncData);
        }

        return response()->json([
            'message' => 'Combo updated successfully',
            'combo' => $combo->load('services.template')
        ]);
    }

    public function deleteCombo($salon_id, $combo_id, Request $request)
    {
        $salon = Salon::findOrFail($salon_id);
        if ($salon->admin_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $combo = \App\Models\Combo::where('salon_id', $salon_id)->findOrFail($combo_id);
        
        // Detach services to clean up pivot table
        $combo->services()->detach();
        
        // Hard delete the combo
        $combo->delete();

        return response()->json(['message' => 'Combo deleted successfully']);
    }

    public function getServiceStaff($salon_id, $service_id, Request $request)
    {
        $salon = Salon::findOrFail($salon_id);
        if ($salon->admin_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $service = Service::where('salon_id', $salon_id)->findOrFail($service_id);
        
        $allStaff = \App\Models\ServiceProvider::with('user')
            ->where('salon_id', $salon_id)
            ->where('is_active', true)
            ->get();

        $assignedStaffIds = $service->providers()->pluck('service_providers.id')->toArray();

        return response()->json([
            'all_staff' => $allStaff,
            'assigned_staff_ids' => $assignedStaffIds
        ]);
    }

    public function assignServiceStaff($salon_id, $service_id, Request $request)
    {
        $salon = Salon::findOrFail($salon_id);
        if ($salon->admin_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $service = Service::where('salon_id', $salon_id)->findOrFail($service_id);

        $validator = Validator::make($request->all(), [
            'staff_ids' => 'present|array',
            'staff_ids.*' => 'uuid|exists:service_providers,id',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $service->providers()->sync($request->staff_ids);

        return response()->json(['message' => 'Staff assigned successfully']);
    }
}
