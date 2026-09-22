<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\ServiceCategory;

class CategoryController extends Controller
{
    public function index()
    {
        // Only fetch active, non-custom categories (master catalog)
        $categories = ServiceCategory::where('is_active', true)
            ->where('is_custom', false)
            // display_order is what SuperAdmin arranges them by; name is only
            // the tie-breaker. Ordering by name alone ignored that entirely.
            ->orderBy('display_order')
            ->orderBy('name')
            ->get();

        return response()->json([
            'categories' => $categories->map(fn (ServiceCategory $category) => [
                'id' => $category->id,
                'name' => $category->name,
                // Rebuilt on the host this request came in on, so the image
                // loads on a phone and an emulator and not just on the machine
                // the icon was uploaded from.
                'icon_url' => $category->publicIconUrl(),
                'display_order' => $category->display_order,
            ]),
        ]);
    }
}
