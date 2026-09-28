<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\Combo;
use App\Models\ServiceCategory;
use App\Services\SearchService;
use Illuminate\Http\Request;

/**
 * The one search a customer uses.
 *
 * Public on purpose: someone deciding whether this app is worth installing an
 * account for should be able to look for a haircut near them first.
 */
class SearchController extends Controller
{
    public function __construct(private SearchService $search)
    {
    }

    public function index(Request $request)
    {
        $data = $request->validate([
            'q' => 'required|string|max:80',
            'city_id' => 'nullable|uuid|exists:cities,id',
            'limit' => 'nullable|integer|min:1|max:50',
            // Narrows the search to a category the customer is browsing, so a
            // search from inside one cannot answer with services from another.
            'category_id' => ['nullable', 'string', 'max:80', function ($attribute, $value, $fail) {
                if (strtolower($value) === Combo::CATEGORY_SENTINEL) {
                    return;
                }

                if (! ServiceCategory::where('id', $value)->where('is_active', true)->exists()) {
                    $fail('That category is not available.');
                }
            }],
        ]);

        $results = $this->search->search(
            $data['q'],
            $data['city_id'] ?? null,
            (int) ($data['limit'] ?? 20),
            $data['category_id'] ?? null,
        );

        return response()->json([
            'success' => true,
            'query' => $data['q'],
        ] + $results + [
            'total' => count($results['services']) + count($results['salons']),
        ]);
    }
}
