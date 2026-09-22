<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

use App\Models\ServiceCategory;
use App\Models\ServiceTemplate;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

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
            'category_id' => 'required|uuid',
            'name' => 'required|string|max:150',
            'estimated_duration_minutes' => 'required|integer|min:30|multiple_of:30',
            'is_active' => 'boolean',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $template = ServiceTemplate::create([
            'category_id' => $request->category_id,
            'name' => $request->name,
            'estimated_duration_minutes' => $request->estimated_duration_minutes,
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

        $category->update([
            'name' => $request->name,
            'icon_url' => $request->icon_url,
            'is_active' => $request->input('is_active', $category->is_active),
            'display_order' => $request->input('display_order', $category->display_order),
        ]);

        return response()->json([
            'message' => 'Category updated successfully',
            'category' => $category
        ]);
    }

    public function deleteCategory($id)
    {
        $category = ServiceCategory::withCount('templates')->findOrFail($id);
        
        if ($category->templates_count > 0) {
            return response()->json([
                'message' => 'Cannot delete category with existing templates'
            ], 400);
        }

        $category->delete();

        return response()->json([
            'message' => 'Category deleted successfully'
        ]);
    }

    public function updateTemplate($id, Request $request)
    {
        $template = ServiceTemplate::findOrFail($id);

        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:150',
            'estimated_duration_minutes' => 'required|integer|min:30|multiple_of:30',
            'is_active' => 'boolean',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $template->update([
            'name' => $request->name,
            'estimated_duration_minutes' => $request->estimated_duration_minutes,
            'is_active' => $request->input('is_active', $template->is_active),
        ]);

        return response()->json([
            'message' => 'Template updated successfully',
            'template' => $template
        ]);
    }

    public function deleteTemplate($id)
    {
        $template = ServiceTemplate::findOrFail($id);
        // Note: Could check if services are using this template before deleting,
        // but typically templates are soft-deleted or cascades apply.
        $template->delete();

        return response()->json([
            'message' => 'Template deleted successfully'
        ]);
    }
}
