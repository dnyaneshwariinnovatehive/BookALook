<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceTemplate;
use App\Support\GenderFocus;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

class CatalogController extends Controller
{
    public function index()
    {
        // Get all categories with their templates
        $categories = ServiceCategory::with(['templates' => function ($query) {
            $query->orderBy('name', 'asc');
        }])->orderBy('is_custom', 'asc') // Standard first
          ->orderBy('name', 'asc')
          ->get();

        // How salons have actually tagged each template, so the dashboard can
        // show what a gender change would touch and flag templates whose name
        // says one thing while the catalogue says Unisex.
        $counts = DB::table('services')
            ->whereNull('deleted_at')
            ->where('is_active', true)
            ->groupBy('template_id', 'gender_focus')
            ->selectRaw('template_id, gender_focus, COUNT(*) as total')
            ->get()
            ->groupBy('template_id');

        foreach ($categories as $category) {
            foreach ($category->templates as $template) {
                $byGender = array_fill_keys(GenderFocus::ALL, 0);

                foreach ($counts->get($template->id, collect()) as $row) {
                    $byGender[GenderFocus::normalise($row->gender_focus)] += (int) $row->total;
                }

                $suggested = $template->gender_focus === GenderFocus::UNISEX
                    ? GenderFocus::suggestFromName($template->name)
                    : null;

                $template->setAttribute('salon_gender_counts', $byGender);
                $template->setAttribute('suggested_gender_focus', $suggested);
            }
        }

        return response()->json([
            'categories' => $categories
        ]);
    }

    /**
     * Store a category icon.
     *
     * The dashboard trims, centres and squares the artwork in the browser
     * before it gets here, because this deployment has neither GD nor Imagick
     * and so cannot transform an image at all. What it *can* do is measure one,
     * and that is what this does: a lopsided or tiny icon is refused with a
     * reason rather than accepted and left to look broken in the customer app.
     *
     * The check is a backstop, not the mechanism. Anything uploaded through the
     * dashboard has already been normalised and sails through it.
     */
    public function uploadIcon(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'icon' => 'required|image|mimes:jpeg,png,jpg,webp,svg|max:2048',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        if (! $request->hasFile('icon')) {
            return response()->json(['message' => 'No file provided'], 400);
        }

        $file = $request->file('icon');
        $extension = strtolower($file->getClientOriginalExtension());

        // An SVG has no pixel dimensions to measure and scales cleanly to any
        // size by definition, so it is taken as-is.
        if ($extension !== 'svg') {
            if ($problem = $this->shapeProblem($file->getPathname())) {
                return response()->json([
                    'message' => $problem,
                    'errors' => ['icon' => [$problem]],
                ], 422);
            }
        }

        $filename = Str::uuid().'.'.$extension;
        $path = $file->storeAs('category_icons', $filename, 'public');

        return response()->json([
            'message' => 'Icon uploaded successfully',
            'url' => asset('storage/'.$path),
        ]);
    }

    /**
     * Why this image would not sit properly in the customer app's tile.
     *
     * Returns null when it is fine. getimagesize() is part of core PHP rather
     * than GD, so this works on a server that cannot process images at all.
     */
    private function shapeProblem(string $path): ?string
    {
        $size = @getimagesize($path);

        if ($size === false) {
            return 'That file could not be read as an image.';
        }

        [$width, $height] = $size;

        if ($width < 128 || $height < 128) {
            return sprintf(
                'That icon is %d×%d. Category icons need to be at least 128×128 or they blur in the app.',
                $width,
                $height
            );
        }

        // The tile is square. A wide or tall image is letterboxed inside it and
        // ends up visibly smaller than its neighbours.
        $ratio = $width / max(1, $height);

        if ($ratio < 0.8 || $ratio > 1.25) {
            return sprintf(
                'That icon is %d×%d, which is not square. Upload it through the category form and it will be squared for you.',
                $width,
                $height
            );
        }

        return null;
    }

    public function storeCategory(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:80',
            'icon_url' => 'nullable|string|max:255',
            'is_active' => 'boolean',
            'display_order' => 'integer',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $category = ServiceCategory::create([
            'name' => $request->name,
            'icon_url' => $request->icon_url,
            'is_custom' => false,
            'is_active' => $request->input('is_active', true),
            'display_order' => $request->input('display_order', 0),
        ]);

        return response()->json([
            'message' => 'Category added to master catalog',
            'category' => $category
        ]);
    }

    public function storeTemplate(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'category_id' => [
                'required',
                'uuid',
                Rule::exists('service_categories', 'id')->whereNull('deleted_at'),
            ],
            'name' => 'required|string|max:150',
            'estimated_duration_minutes' => 'required|integer|min:30|multiple_of:30',
            'gender_focus' => 'nullable|'.GenderFocus::rule(),
            'is_active' => 'boolean',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $template = ServiceTemplate::create([
            'category_id' => $request->category_id,
            'name' => $request->name,
            'estimated_duration_minutes' => $request->estimated_duration_minutes,
            'gender_focus' => $request->input('gender_focus') ?? GenderFocus::UNISEX,
            'is_custom' => false,
            'is_active' => $request->input('is_active', true),
        ]);

        return response()->json([
            'message' => 'Service template added to master catalog',
            'template' => $template
        ]);
    }

    public function promoteCategory($id, Request $request)
    {
        $category = ServiceCategory::findOrFail($id);
        
        if (!$category->is_custom) {
            return response()->json(['message' => 'Category is already standard'], 400);
        }

        $category->is_custom = false;
        $category->promoted_to_standard_at = now();
        $category->promoted_by = $request->user()->id;
        $category->save();

        return response()->json([
            'message' => 'Category promoted successfully',
            'category' => $category
        ]);
    }

    public function promoteTemplate($id, Request $request)
    {
        $template = ServiceTemplate::findOrFail($id);
        
        if (!$template->is_custom) {
            return response()->json(['message' => 'Template is already standard'], 400);
        }

        $template->is_custom = false;
        $template->promoted_to_standard_at = now();
        $template->promoted_by = $request->user()->id;
        $template->save();

        return response()->json([
            'message' => 'Template promoted successfully',
            'template' => $template
        ]);
    }
    public function updateCategory($id, Request $request)
    {
        $category = ServiceCategory::findOrFail($id);

        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:80',
            'icon_url' => 'nullable|string|max:255',
            'is_active' => 'boolean',
            'display_order' => 'integer',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $changes = [
            'name' => $request->name,
            'is_active' => $request->input('is_active', $category->is_active),
            'display_order' => $request->input('display_order', $category->display_order),
        ];

        // Only a request that names the icon changes it. Sending null clears
        // it on purpose; leaving the key out keeps whatever is there.
        if ($request->exists('icon_url')) {
            $changes['icon_url'] = $request->icon_url;
        }

        $category->update($changes);

        return response()->json([
            'message' => 'Category updated successfully',
            'category' => $category
        ]);
    }

    public function deleteCategory($id, Request $request)
    {
        $category = ServiceCategory::with('templates')->find($id);

        if (! $category) {
            return response()->json([
                'message' => 'Category not found'
            ], 404);
        }

        try {
            DB::transaction(function () use ($category) {
                // Retire all templates associated with this category
                foreach ($category->templates as $template) {
                    // Retire linked salon services
                    $linkedServices = Service::where('template_id', $template->id)->get();
                    foreach ($linkedServices as $service) {
                        $service->is_active = false;
                        $service->save();
                        $service->delete();
                    }

                    // Remove from active first-time offers
                    DB::table('first_time_offer_services')
                        ->where('service_template_id', $template->id)
                        ->delete();

                    // Retire the template itself
                    $template->is_active = false;
                    $template->save();
                    $template->delete();
                }

                // Retire the category itself
                $category->is_active = false;
                $category->save();
                $category->delete();
            });

            return response()->json([
                'message' => 'Category and associated templates retired successfully'
            ], 200);
        } catch (\Throwable $e) {
            Log::error('Failed to retire service category: ' . $e->getMessage(), [
                'category_id' => $id,
                'exception' => $e
            ]);

            return response()->json([
                'message' => 'Failed to delete category due to an internal server error.'
            ], 500);
        }
    }

    public function updateTemplate($id, Request $request)
    {
        $template = ServiceTemplate::findOrFail($id);

        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:150',
            'estimated_duration_minutes' => 'required|integer|min:30|multiple_of:30',
            'gender_focus' => 'nullable|'.GenderFocus::rule(),
            'is_active' => 'boolean',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $gender = $request->input('gender_focus') ?? $template->gender_focus;
        $servicesUpdated = 0;
        $salonConflicts = 0;

        DB::transaction(function () use ($template, $request, $gender, &$servicesUpdated, &$salonConflicts) {
            $template->update([
                'name' => $request->name,
                'estimated_duration_minutes' => $request->estimated_duration_minutes,
                'gender_focus' => $gender,
                'is_active' => $request->input('is_active', $template->is_active),
            ]);

            // A gendered template is that gender in every salon. Salon copies
            // that said otherwise follow it, deleted ones too, so a restore
            // never brings back a contradiction. Going back to Unisex leaves
            // salons' own narrowing alone.
            if ($gender === GenderFocus::UNISEX) {
                return;
            }

            $servicesUpdated = Service::withTrashed()
                ->where('template_id', $template->id)
                ->where('gender_focus', '!=', $gender)
                ->update(['gender_focus' => $gender]);

            // A single-gender salon of the other gender now holds a service it
            // cannot serve. That is the owner's call to resolve, not ours to
            // delete, so it is only counted and reported.
            $salonConflicts = Service::where('services.template_id', $template->id)
                ->where('services.is_active', true)
                ->join('salons', 'salons.id', '=', 'services.salon_id')
                ->whereIn('salons.gender_focus', [GenderFocus::MEN, GenderFocus::WOMEN])
                ->where('salons.gender_focus', '!=', $gender)
                ->count();
        });

        return response()->json([
            'message' => 'Template updated successfully',
            'template' => $template->fresh(),
            'services_updated' => $servicesUpdated,
            'salon_conflicts' => $salonConflicts,
        ]);
    }

    public function deleteTemplate($id, Request $request)
    {
        $template = ServiceTemplate::find($id);

        if (! $template) {
            return response()->json([
                'message' => 'Service template not found'
            ], 404);
        }

        try {
            DB::transaction(function () use ($template) {
                // Retire linked salon services
                $linkedServices = Service::where('template_id', $template->id)->get();
                foreach ($linkedServices as $service) {
                    $service->is_active = false;
                    $service->save();
                    $service->delete();
                }

                // Remove from active first-time offers
                DB::table('first_time_offer_services')
                    ->where('service_template_id', $template->id)
                    ->delete();

                // Retire the template itself
                $template->is_active = false;
                $template->save();
                $template->delete();
            });

            return response()->json([
                'message' => 'Service template retired successfully'
            ], 200);
        } catch (\Throwable $e) {
            Log::error('Failed to retire service template: ' . $e->getMessage(), [
                'template_id' => $id,
                'exception' => $e
            ]);

            return response()->json([
                'message' => 'Failed to delete template due to an internal server error.'
            ], 500);
        }
    }
}
