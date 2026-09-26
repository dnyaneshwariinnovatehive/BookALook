<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\Review;
use App\Models\Salon;
use App\Services\ReviewService;
use Illuminate\Http\Request;

/**
 * Ratings across the whole platform.
 *
 * SuperAdmin's question is not "how is this salon doing" — the salon's own page
 * answers that. It is "which salons are dragging the platform down", which is
 * why this leads with the worst-rated salons that have enough ratings to be
 * judged on, rather than with an overall average nobody can act on.
 */
class PlatformReviewController extends Controller
{
    /**
     * A salon needs at least this many ratings before its average says
     * anything. One disappointed customer is not a failing business.
     */
    private const CREDIBLE_AT = 3;

    public function __construct(private ReviewService $reviews)
    {
    }

    /**
     * Columns SuperAdmin is allowed to sort on. Ratings are aggregated, so this
     * cannot become an ORDER BY on the salons table — it is applied to the
     * shaped rows instead.
     */
    private const SORTABLE = ['name', 'average', 'review_count', 'status'];

    public function index(Request $request)
    {
        $request->validate([
            // Curated, business-meaningful orderings.
            'sort' => 'nullable|in:worst,best,most_rated,recent',
            // Raw column sort, driven by clicking a table header.
            'column' => 'nullable|in:' . implode(',', self::SORTABLE),
            'direction' => 'nullable|in:asc,desc',
            'search' => 'nullable|string|max:100',
            'page' => 'nullable|integer|min:1',
            'per_page' => 'nullable|integer|min:5|max:100',
        ]);

        $sort = $request->input('sort', 'worst');

        $salons = Salon::query()
            ->withCount('reviews')
            ->withAvg('reviews', 'rating')
            ->when($request->filled('search'), fn ($q) => $q->where('name', 'like', "%{$request->search}%"))
            ->has('reviews')
            ->get()
            ->map(fn (Salon $salon) => [
                'id' => $salon->id,
                'name' => $salon->name,
                'status' => $salon->status,
                'review_count' => (int) $salon->reviews_count,
                'average' => round((float) $salon->reviews_avg_rating, 1),
                // Below this, the average is not yet worth acting on — the UI
                // says so rather than ranking a salon bottom on two ratings.
                'is_credible' => $salon->reviews_count >= self::CREDIBLE_AT,
            ]);

        $column = $request->input('column');
        $descending = $request->input('direction') !== 'asc';

        if ($column && in_array($column, self::SORTABLE, true)) {
            // An explicit header click wins over the curated preset.
            $sorted = $descending
                ? $salons->sortByDesc($column, SORT_NATURAL)
                : $salons->sortBy($column, SORT_NATURAL);
        } else {
            $sorted = match ($sort) {
                'best' => $salons->sortByDesc('average'),
                'most_rated' => $salons->sortByDesc('review_count'),
                // Credible salons first within the worst list, so a salon with two
                // one-star ratings does not bury one with thirty.
                'worst' => $salons->sortBy([
                    fn ($a, $b) => ($b['is_credible'] ? 1 : 0) <=> ($a['is_credible'] ? 1 : 0),
                    fn ($a, $b) => $a['average'] <=> $b['average'],
                ]),
                default => $salons->sortByDesc('review_count'),
            };
        }

        $all = Review::selectRaw('count(*) as total, avg(rating) as average')->first();

        // Ratings are aggregated in PHP, so pagination happens after ordering.
        // The platform stats below still describe every rated salon, not the page.
        $perPage = (int) ($request->input('per_page') ?? 20);
        $total = $sorted->count();
        $lastPage = max(1, (int) ceil($total / $perPage));
        $page = min(max(1, (int) ($request->input('page') ?? 1)), $lastPage);

        return response()->json([
            'success' => true,
            'platform' => [
                'total_reviews' => (int) $all->total,
                'average' => $all->total > 0 ? round((float) $all->average, 2) : 0,
                'rated_salons' => $total,
                'salons_below_three' => $salons->where('is_credible', true)->where('average', '<', 3)->count(),
            ],
            'data' => $sorted->slice(($page - 1) * $perPage, $perPage)->values(),
            'meta' => [
                'current_page' => $page,
                'last_page' => $lastPage,
                'per_page' => $perPage,
                'total' => $total,
            ],
        ]);
    }

    /** Every review for one salon, for when SuperAdmin needs to read them. */
    public function forSalon(Request $request, string $salonId)
    {
        if (! Salon::where('id', $salonId)->exists()) {
            return response()->json(['success' => false, 'message' => 'Salon not found.'], 404);
        }

        $list = $this->reviews->listFor(
            $salonId,
            (int) $request->input('page', 1),
            20,
            $request->filled('rating') ? (int) $request->rating : null,
            $request->boolean('with_comment')
        );

        return response()->json([
            'success' => true,
            'summary' => $this->reviews->summaryFor($salonId),
        ] + $list);
    }
}
