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

    public function index(Request $request)
    {
        $request->validate([
            'sort' => 'nullable|in:worst,best,most_rated,recent',
            'search' => 'nullable|string|max:100',
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

        $all = Review::selectRaw('count(*) as total, avg(rating) as average')->first();

        return response()->json([
            'success' => true,
            'platform' => [
                'total_reviews' => (int) $all->total,
                'average' => $all->total > 0 ? round((float) $all->average, 2) : 0,
                'rated_salons' => $salons->count(),
                'salons_below_three' => $salons->where('is_credible', true)->where('average', '<', 3)->count(),
            ],
            'data' => $sorted->values(),
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
