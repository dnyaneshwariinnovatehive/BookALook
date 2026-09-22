<?php

namespace App\Services;

use App\Models\Appointment;
use App\Models\Review;
use App\Models\Salon;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * Ratings, and keeping every surface that shows one telling the same story.
 *
 * The number on a salon's card in the explore list comes from salons.avg_rating,
 * because sorting thousands of salons by a live average would mean aggregating
 * the whole reviews table on every search. The number on the salon's own page
 * is computed from the reviews themselves. Those two only agree if something
 * writes the denormalised copy back every time a review lands — which nothing
 * did, so the list has been showing whatever the seeder happened to set.
 *
 * Every write goes through here so that cannot drift again.
 */
class ReviewService
{
    /**
     * How far back the app will *ask* about an unrated visit.
     *
     * This bounds the prompt, not the right to review. Being nagged on opening
     * about a haircut from three months ago is irritating; being refused when
     * you go looking for that same haircut to review it is worse. So the
     * unprompted route stays open forever and only the interruption expires.
     */
    public const REVIEW_WINDOW_DAYS = 30;

    /**
     * Record a customer's verdict and bring the salon's headline figures with
     * it.
     */
    public function record(Appointment $appointment, int $rating, ?string $comment): Review
    {
        $review = Review::create([
            'appointment_id' => $appointment->id,
            'customer_id' => $appointment->customer_id,
            'salon_id' => $appointment->salon_id,
            'rating' => $rating,
            'comment' => filled($comment) ? trim($comment) : null,
        ]);

        $this->refreshSalonRating($appointment->salon_id);

        return $review;
    }

    /**
     * Write the live average back onto the salon, so lists and cards match the
     * salon's own page.
     */
    public function refreshSalonRating(string $salonId): void
    {
        $stats = Review::where('salon_id', $salonId)
            ->selectRaw('count(*) as total, avg(rating) as average')
            ->first();

        Salon::where('id', $salonId)->update([
            'review_count' => (int) $stats->total,
            'avg_rating' => $stats->total > 0 ? round((float) $stats->average, 2) : 0,
        ]);
    }

    /**
     * Visits this customer has had but not yet rated.
     *
     * Drives the prompt the app shows on opening, so it is bounded by
     * REVIEW_WINDOW_DAYS — anything older is still reviewable from the Past
     * list, it just stops interrupting people. Ordered oldest first so a
     * customer with a backlog is asked about the visit they are least likely to
     * remember before it falls out of the prompt entirely.
     *
     * @return Collection<int, Appointment>
     */
    public function awaitingReview(string $customerId, int $limit = 5): Collection
    {
        return Appointment::with(['salon:id,name,cover_photo_url', 'appointedProvider.user:id,name'])
            ->where('customer_id', $customerId)
            ->where('status', 'completed')
            ->whereDate('appointment_date', '>=', Carbon::today()->subDays(self::REVIEW_WINDOW_DAYS))
            ->whereDoesntHave('review')
            ->orderBy('appointment_date')
            ->limit($limit)
            ->get();
    }

    /**
     * Whether this appointment can still be rated, and why not if it cannot.
     *
     * @return array{allowed: bool, reason: ?string}
     */
    public function reviewability(Appointment $appointment): array
    {
        if ($appointment->status !== 'completed') {
            return ['allowed' => false, 'reason' => 'You can only review a visit once it is finished.'];
        }

        if ($appointment->review()->exists()) {
            return ['allowed' => false, 'reason' => 'You have already reviewed this visit.'];
        }

        // Deliberately no age limit. A finished visit that has never been rated
        // can be rated whenever the customer gets round to it — the Past list
        // is exactly where someone goes to do that, and offering the history
        // but refusing to let them speak about most of it is a dead end.
        // REVIEW_WINDOW_DAYS still bounds the prompt in awaitingReview().
        return ['allowed' => true, 'reason' => null];
    }

    /**
     * The whole rating picture for one salon: the headline, the distribution
     * behind it, and the reviews themselves.
     *
     * The distribution matters more than the average. Four stars made of
     * straight fours is a different salon from four stars made of fives and
     * ones, and a customer deciding where to go deserves to see which they are
     * looking at.
     *
     * @return array<string, mixed>
     */
    public function summaryFor(string $salonId): array
    {
        $reviews = Review::where('salon_id', $salonId)->get(['rating', 'comment']);
        $total = $reviews->count();

        $breakdown = [];
        for ($star = 5; $star >= 1; $star--) {
            $count = $reviews->where('rating', $star)->count();
            $breakdown[$star] = [
                'count' => $count,
                'percent' => $total > 0 ? (int) round($count / $total * 100) : 0,
            ];
        }

        return [
            'average' => $total > 0 ? round($reviews->avg('rating'), 1) : 0.0,
            'count' => $total,
            'with_comment_count' => $reviews->filter(fn ($r) => filled($r->comment))->count(),
            'breakdown' => $breakdown,
        ];
    }

    /**
     * Reviews for a salon, newest first, shaped for reading.
     *
     * Only a first name reaches the public list. A review is a public statement
     * about a business, not an invitation to identify the person who made it.
     *
     * @return array<string, mixed>
     */
    /**
     * How a list of reviews may be ordered.
     *
     * Newest first is the default because a salon owner opening this page is
     * usually asking "what has just been said about me". The other three exist
     * for the other question — "what is the worst of it" — which is the one
     * that actually needs acting on.
     */
    public const SORTS = [
        'recent' => 'Newest first',
        'oldest' => 'Oldest first',
        'highest' => 'Highest rated',
        'lowest' => 'Lowest rated',
    ];

    /**
     * @param  string|null  $sort  One of SORTS. Anything else falls back to
     *                             newest first rather than failing: an unknown
     *                             sort is a bad request, not a reason to show
     *                             an owner an error instead of their reviews.
     */
    public function listFor(
        string $salonId,
        int $page,
        int $perPage,
        ?int $starFilter,
        bool $onlyWithComment,
        ?string $sort = null,
    ): array {
        $query = Review::with('customer:id,name')
            ->where('salon_id', $salonId);

        // created_at resolves to the second, and a salon can take several
        // reviews in one, so id breaks the tie and keeps paging stable —
        // without it a row can appear on two pages or on neither.
        match ($sort) {
            'oldest' => $query->orderBy('created_at')->orderBy('id'),
            'highest' => $query->orderByDesc('rating')->orderByDesc('created_at')->orderByDesc('id'),
            'lowest' => $query->orderBy('rating')->orderByDesc('created_at')->orderByDesc('id'),
            default => $query->orderByDesc('created_at')->orderByDesc('id'),
        };

        if ($starFilter !== null) {
            $query->where('rating', $starFilter);
        }

        if ($onlyWithComment) {
            $query->whereNotNull('comment')->where('comment', '!=', '');
        }

        $paginated = $query->paginate($perPage, ['*'], 'page', $page);

        return [
            'reviews' => collect($paginated->items())->map(fn (Review $review) => [
                'id' => $review->id,
                'rating' => $review->rating,
                'comment' => $review->comment,
                'customer_name' => $this->publicName($review->customer?->name),
                'created_at' => $review->created_at,
                'age_label' => $this->ageLabel($review->created_at),
            ])->values(),
            'meta' => [
                'current_page' => $paginated->currentPage(),
                'last_page' => $paginated->lastPage(),
                'per_page' => $paginated->perPage(),
                'total' => $paginated->total(),
                'has_more' => $paginated->hasMorePages(),
                // Echoed back so the app can show what it is actually looking
                // at rather than what it believes it asked for.
                'sort' => array_key_exists((string) $sort, self::SORTS) ? $sort : 'recent',
                'rating' => $starFilter,
                'with_comment' => $onlyWithComment,
            ],
        ];
    }

    /** "Priya S." — enough to read as a person, not enough to find them. */
    public function publicName(?string $name): string
    {
        $name = trim((string) $name);

        if ($name === '') {
            return 'Customer';
        }

        $parts = preg_split('/\s+/', $name);

        return count($parts) === 1
            ? $parts[0]
            : $parts[0] . ' ' . strtoupper(substr(end($parts), 0, 1)) . '.';
    }

    /**
     * "3 days ago". Written out rather than left as a date because a reader is
     * judging whether a review is still relevant, not looking it up.
     */
    public function ageLabel(?Carbon $when): string
    {
        if (! $when) {
            return '';
        }

        $days = (int) $when->startOfDay()->diffInDays(Carbon::today());

        return match (true) {
            $days <= 0 => 'Today',
            $days === 1 => 'Yesterday',
            $days < 7 => "{$days} days ago",
            $days < 14 => 'Last week',
            $days < 31 => floor($days / 7) . ' weeks ago',
            $days < 60 => 'Last month',
            $days < 365 => floor($days / 30) . ' months ago',
            $days < 730 => 'Last year',
            default => floor($days / 365) . ' years ago',
        };
    }
}
