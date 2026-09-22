<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
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
        ]);

        $results = $this->search->search(
            $data['q'],
            $data['city_id'] ?? null,
            (int) ($data['limit'] ?? 20),
        );

        return response()->json([
            'success' => true,
            'query' => $data['q'],
        ] + $results + [
            'total' => count($results['services']) + count($results['salons']),
        ]);
    }
}
