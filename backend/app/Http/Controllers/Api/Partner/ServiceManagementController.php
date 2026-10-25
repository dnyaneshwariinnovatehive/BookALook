<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceTemplate;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Support\GenderFocus;
use Illuminate\Support\Str;

class ServiceManagementController extends Controller
{
    public function getMasterCatalog($salon_id, Request $request)
    {
        $salon = Salon::findOrFail($salon_id);
        if ($salon->admin_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized for this salon'], 403);
        }

        // Every standard category, plus the custom ones this salon made. The
        // salon is the one in the path, which the owner check above vouches
        // for, never one the caller names in the query string.
        $salonId = $salon->id;

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

        $categories = $query->get();

        // Each template says which genders this salon may offer it as, so the
        // app can lock the picker. One this salon cannot offer at all — a Men
        // Only template in a Women Only salon — is left out entirely.
        foreach ($categories as $category) {
            $offerable = $category->templates
                ->filter(function (ServiceTemplate $template) use ($salon) {
                    $allowed = GenderFocus::allowedFor($template->gender_focus, $salon->gender_focus);

                    $template->setAttribute('allowed_gender_focus', $allowed);
                    $template->setAttribute('default_gender_focus', $allowed[0] ?? null);

                    return $allowed !== [];
                })
                ->values();

            $category->setRelation('templates', $offerable);
        }

        return response()->json([
            'categories' => $categories,
            'salon_gender_focus' => GenderFocus::normalise($salon->gender_focus),
            // What a brand-new custom service may be, which is everything a
            // Unisex template could be narrowed to here.
            'custom_allowed_gender_focus' => GenderFocus::allowedFor(GenderFocus::UNISEX, $salon->gender_focus),
        ]);
    }

    public function getSalonServices($salon_id, Request $request)
    {
        // Ensure user is authorized for this salon
        $salon = Salon::findOrFail($salon_id);
        if ($salon->admin_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized for this salon'], 403);
        }

        $services = Service::with(['template.category', 'upsells:id'])
            ->where('salon_id', $salon_id)
            ->where('is_active', true)
            ->get()
            ->map(fn (Service $service) => $this->withUpsellIds($service));

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

        $unassigned = Service::getUnassignedForSalon($salon_id);

        return response()->json([
            'grouped_services' => array_values($grouped),
            'unassigned_services' => Service::formatUnassigned($unassigned),
        ]);
    }

    public function getUnassignedServices($salon_id, Request $request)
    {
        $salon = Salon::findOrFail($salon_id);
        if ($salon->admin_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized for this salon'], 403);
        }

        $unassigned = Service::getUnassignedForSalon($salon_id);

        return response()->json([
            'unassigned_services' => Service::formatUnassigned($unassigned),
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
            'gender_focus' => 'nullable|string|'.GenderFocus::rule(),
            'will_refund_advance_if_cancelled' => 'nullable|boolean',
            // Add-ons the owner recommends with this service.
            'linked_service_ids' => 'sometimes|nullable|array|max:'.self::MAX_UPSELLS,
            'linked_service_ids.*' => 'string',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $advancePercentage = $request->has('advance_percentage') && $request->advance_percentage !== null
            ? (float) $request->advance_percentage
            : null;

        if (($advancePercentage === null || $advancePercentage <= 0) && $request->boolean('will_refund_advance_if_cancelled')) {
            return response()->json([
                'message' => 'Refund advance cannot be enabled when minimum advance is 0%.',
                'errors' => ['will_refund_advance_if_cancelled' => ['Refund advance cannot be enabled when minimum advance is 0%.']]
            ], 422);
        }

        $willRefund = ($advancePercentage !== null && $advancePercentage > 0)
            ? (bool) ($request->will_refund_advance_if_cancelled ?? false)
            : false;

        $templateId = $request->template_id;

        // A custom template is born here, so it has no gender of its own yet:
        // it may be anything a Unisex template could be narrowed to.
        $templateGender = GenderFocus::UNISEX;

        if ($request->is_custom) {
            $customName = trim($request->custom_template_name ?? '');
            $normalizedCustomName = mb_strtolower($customName);

            // Check if active service with this name already exists in this salon
            $alreadyExists = Service::where('salon_id', $salon_id)
                ->where('is_active', true)
                ->whereHas('template', function ($q) use ($normalizedCustomName) {
                    $q->whereRaw('LOWER(TRIM(name)) = ?', [$normalizedCustomName]);
                })
                ->exists();

            if ($alreadyExists) {
                return response()->json(['message' => 'A service with this name already exists in this salon'], 400);
            }

            $categoryId = $request->category_id;

            // A custom service goes into a category this salon can see: a
            // live standard one, or one of its own. Never another salon's.
            if ($categoryId !== 'new_custom' && ! $this->categoryAvailableTo($categoryId, $salon_id)) {
                return response()->json([
                    'message' => 'That category is not available to this salon.',
                    'errors' => ['category_id' => ['That category is not available to this salon.']],
                ], 422);
            }
        } else {
            $template = ServiceTemplate::with('category')->find($templateId);

            // Retired, switched off, or another salon's own: as far as this
            // salon is concerned, it does not exist.
            if (! $template || ! $this->templateAvailableTo($template, $salon_id)) {
                return response()->json(['message' => 'Service template not found'], 404);
            }
            $templateGender = $template->gender_focus;
            $normalizedTemplateName = mb_strtolower(trim($template->name));

            // Check if active service with this template ID or identical template name exists
            $alreadyExists = Service::where('salon_id', $salon_id)
                ->where('is_active', true)
                ->where(function ($q) use ($templateId, $normalizedTemplateName) {
                    $q->where('template_id', $templateId)
                      ->orWhereHas('template', function ($sub) use ($normalizedTemplateName) {
                          $sub->whereRaw('LOWER(TRIM(name)) = ?', [$normalizedTemplateName]);
                      });
                })
                ->exists();

            if ($alreadyExists) {
                return response()->json(['message' => 'This service already exists in this salon'], 400);
            }
        }

        $gender = $request->gender_focus ?? GenderFocus::defaultFor($templateGender, $salon->gender_focus);

        if ($problem = $this->genderProblem($templateGender, $salon, $gender)) {
            return $problem;
        }

        $details = [
            'price' => $request->price,
            'description' => $request->description,
            'advance_percentage' => $advancePercentage,
            'gender_focus' => $gender,
            'will_refund_advance_if_cancelled' => $willRefund,
        ];

        // The custom category, its template and the service land together or
        // not at all, so a failure part-way leaves no orphan behind.
        $service = DB::transaction(function () use ($request, $salon_id, $templateId, $details) {
            if ($request->is_custom) {
                $categoryId = $request->category_id;

                if ($categoryId === 'new_custom') {
                    $categoryId = ServiceCategory::create([
                        'name' => $request->custom_category_name,
                        'is_custom' => true,
                        'created_by_salon_id' => $salon_id,
                    ])->id;
                }

                $templateId = ServiceTemplate::create([
                    'category_id' => $categoryId,
                    'name' => $request->custom_template_name,
                    'estimated_duration_minutes' => $request->estimated_duration_minutes,
                    'gender_focus' => $details['gender_focus'],
                    'is_custom' => true,
                    'created_by_salon_id' => $salon_id,
                ])->id;
            }

            // Check if service already exists (including soft-deleted ones)
            $exists = Service::withTrashed()->where('salon_id', $salon_id)->where('template_id', $templateId)->first();

            if (! $exists) {
                return Service::create($details + [
                    'salon_id' => $salon_id,
                    'template_id' => $templateId,
                ]);
            }

            if (! $exists->trashed()) {
                return null;
            }

            // If it was soft-deleted, restore it and update the details
            $exists->restore();
            $exists->update($details + ['is_active' => true]);

            return $exists;
        });

        if (! $service) {
            return response()->json(['message' => 'Service already exists in this salon'], 400);
        }

        if ($request->has('linked_service_ids')) {
            $this->syncUpsells($service, (array) $request->input('linked_service_ids', []));
        }

        return response()->json([
            'message' => 'Service added successfully',
            'service' => $this->withUpsellIds($service->load('template.category')),
        ]);
    }

    /**
     * Whether a salon may file a custom service under this category: it must
     * still be live, and be either standard or this salon's own.
     */
    private function categoryAvailableTo($categoryId, string $salonId): bool
    {
        if (! is_string($categoryId) || ! Str::isUuid($categoryId)) {
            return false;
        }

        return ServiceCategory::where('id', $categoryId)
            ->where('is_active', true)
            ->where(function ($q) use ($salonId) {
                $q->where('is_custom', false)
                  ->orWhere('created_by_salon_id', $salonId);
            })
            ->exists();
    }

    /**
     * Whether a salon may offer this template: it, and the category it sits
     * in, must be live, and a custom one must be this salon's own.
     */
    private function templateAvailableTo(ServiceTemplate $template, string $salonId): bool
    {
        if (! $template->is_active) {
            return false;
        }

        if ($template->is_custom && $template->created_by_salon_id !== $salonId) {
            return false;
        }

        $category = $template->category;

        return $category && ! $category->trashed() && $category->is_active;
    }

    /** How many add-ons one service may recommend. */
    private const MAX_UPSELLS = 10;

    /**
     * Make these the service's recommended add-ons, in the order given.
     *
     * Only the same salon's live services count, never the service itself and
     * never twice; anything else in the list is dropped rather than refused,
     * so a stale id from an old screen cannot fail the whole save.
     */
    private function syncUpsells(Service $service, array $ids): void
    {
        $ids = array_values(array_unique(array_filter(
            array_map('strval', $ids),
            fn ($id) => $id !== '' && $id !== (string) $service->id
        )));

        $valid = $ids === [] ? [] : Service::where('salon_id', $service->salon_id)
            ->where('is_active', true)
            ->whereIn('id', $ids)
            ->pluck('id')
            ->map(fn ($id) => (string) $id)
            ->all();

        $sync = [];
        foreach ($ids as $order => $id) {
            if (in_array($id, $valid, true)) {
                $sync[$id] = ['display_order' => $order];
            }
        }

        $service->upsells()->sync($sync);
    }

    /** The service as the partner app reads it, with its add-on ids. */
    private function withUpsellIds(Service $service): Service
    {
        $ids = $service->relationLoaded('upsells')
            ? $service->upsells->pluck('id')
            : $service->upsells()->pluck('services.id');

        $service->setAttribute('linked_service_ids', $ids->map(fn ($id) => (string) $id)->values()->all());
        $service->unsetRelation('upsells');

        return $service;
    }

    /**
     * Why this salon may not offer a service of this template as this gender,
     * as the response to send back; null when it may.
     */
    private function genderProblem(?string $templateGender, Salon $salon, ?string $gender)
    {
        $allowed = GenderFocus::allowedFor($templateGender, $salon->gender_focus);

        if ($allowed === []) {
            $message = sprintf(
                'This is a %s service and your salon is %s.',
                GenderFocus::normalise($templateGender),
                GenderFocus::normalise($salon->gender_focus)
            );
        } elseif (! in_array($gender, $allowed, true)) {
            $message = count($allowed) === 1
                ? "This service can only be offered as {$allowed[0]}."
                : 'This service can only be offered as '.implode(', ', $allowed).'.';
        } else {
            return null;
        }

        return response()->json([
            'message' => $message,
            'errors' => ['gender_focus' => [$message]],
            'allowed_gender_focus' => $allowed,
        ], 422);
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
            'gender_focus' => 'sometimes|string|'.GenderFocus::rule(),
            'linked_service_ids' => 'sometimes|nullable|array|max:'.self::MAX_UPSELLS,
            'linked_service_ids.*' => 'string',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        if ($request->has('gender_focus')) {
            $templateGender = $service->template->gender_focus ?? GenderFocus::UNISEX;

            // A salon's own custom template follows its one service, so its
            // gender is the owner's to change, within the salon's own focus.
            if ($service->template && $service->template->is_custom) {
                $templateGender = GenderFocus::UNISEX;
            }

            if ($problem = $this->genderProblem($templateGender, $salon, $request->gender_focus)) {
                return $problem;
            }

            $service->gender_focus = $request->gender_focus;

            if ($service->template && $service->template->is_custom && $service->template->created_by_salon_id === $salon->id) {
                $service->template->update(['gender_focus' => $request->gender_focus]);
            }
        }

        if ($request->has('price')) $service->price = $request->price;
        if ($request->has('description')) $service->description = $request->description;

        $service->save();

        // Present means "these are the add-ons now" — an empty list clears them.
        if ($request->has('linked_service_ids')) {
            $this->syncUpsells($service, (array) $request->input('linked_service_ids', []));
        }

        return response()->json([
            'message' => 'Service updated successfully',
            'service' => $this->withUpsellIds($service->load('template.category'))
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

        $comboLimit = \App\Models\PlatformPolicySetting::value('combos_limit_per_salon', 10);
        $currentCombosCount = \App\Models\Combo::where('salon_id', $salon_id)->where('is_active', true)->count();

        if ($currentCombosCount >= $comboLimit) {
            return response()->json([
                'message' => "You have reached the maximum limit of {$comboLimit} combos allowed per salon."
            ], 403);
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
        
        // Mark as inactive instead of deleting to preserve financial/appointment history
        $combo->is_active = false;
        $combo->save();

        return response()->json(['message' => 'Combo deleted successfully']);
    }

    public function getServiceStaff($salon_id, $service_id, Request $request)
    {
        $salon = Salon::findOrFail($salon_id);
        if ($salon->admin_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $service = Service::where('salon_id', $salon_id)->findOrFail($service_id);
        
        $adminId = $salon->admin_id;

        $allStaff = \App\Models\ServiceProvider::with('user')
            ->where(function ($q) use ($salon_id, $adminId) {
                $q->where('salon_id', $salon_id)
                  ->orWhere(function ($adminQ) use ($adminId) {
                      $adminQ->where('user_id', $adminId);
                  });
            })
            ->where('is_active', true)
            ->whereNull('deleted_at')
            ->get();

        $allStaff->each(function ($provider) use ($adminId) {
            $provider->is_admin_provider = ($adminId && $provider->user_id === $adminId);
        });

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

        // If one of the staff_ids belongs to the admin provider, ensure salon_id is set
        $adminId = $salon->admin_id;
        $providers = ServiceProvider::whereIn('id', $request->staff_ids)->get();
        foreach ($providers as $p) {
            if ($p->user_id === $adminId && ($p->salon_id !== $salon_id || !$p->is_active)) {
                $p->salon_id = $salon_id;
                $p->is_active = true;
                $p->save();
            }
        }

        $service->providers()->sync($request->staff_ids);

        return response()->json(['message' => 'Staff assigned successfully']);
    }
}
