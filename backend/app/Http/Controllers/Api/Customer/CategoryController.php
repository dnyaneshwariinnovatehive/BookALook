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
            ->orderBy('name', 'asc')
            ->get();

        return response()->json([
            'categories' => $categories
        ]);
    }
}
