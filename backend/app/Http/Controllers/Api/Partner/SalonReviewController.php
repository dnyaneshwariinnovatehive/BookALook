<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\Review;
use App\Models\Salon;
use App\Services\ReviewService;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

/**
 * What a salon owner is told about their own ratings.
 *
 * An owner does not need a statistics page. They need to know three things:
 * how they are doing, whether that is better or worse than it was, and what
 * anybody actually said. So the numbers are few and each one is labelled in
 * words — "4.6 out of 5 from 38 customers", "up from 4.2 last month" — rather
 * than left as figures to interpret.
 */
class SalonReviewController extends Controller
{
    public function __construct(private ReviewService $reviews)
    {
    }

    public function index(Request $request, string $salonId)
    {
        if ($denied = $this->denyUnlessOfTheSalon($request, $salonId)) {
            return $denied;
        }

        $request->validate([
            'page' => 'nullable|integer|min:1',
            'per_page' => 'nullable|integer|min:5|max:50',
            'rating' => 'nullable|integer|min:1|max:5',
            'with_comment' => 'nullable|boolean',
            'sort' => 'nullable|string|in:'.implode(',', array_keys(ReviewService::SORTS)),
        ]);

        $summary = $this->reviews->summaryFor($salonId);

        $list = $this->reviews->listFor(
            $salonId,
            (int) $request->input('page', 1),
            (int) $request->input('per_page', 20),
            $request->filled('rating') ? (int) $request->rating : null,
            $request->boolean('with_comment'),
            $request->input('sort'),
        );

        return response()->json([
            'success' => true,
            'summary' => $summary + [
                'headline' => $this->headline($summary),
                'trend' => $this->trend($salonId),
            ],
            // So the app can build the sort menu from the server's list rather
            // than keeping its own copy in step by hand.
            'sorts' => ReviewService::SORTS,
        ] + $list);
    }

    /**
     * The one sentence an owner should be able to read and stop.
     */
    private function headline(array $summary): string
    {
        if ($summary['count'] === 0) {
            return 'No ratings yet. They start arriving once customers finish their appointments.';
        }

        $people = $summary['count'] === 1 ? 'customer' : 'customers';

        return sprintf(
            '%s out of 5, from %d %s.',
            number_format((float) $summary['average'], 1),
            $summary['count'],
            $people
        );
    }

    /**
     * This month against last, in words.
     *
     * Deliberately not a chart. An owner glancing at their phone between
     * customers needs "slightly better than last month", not a line graph — and
     * a month with two ratings in it cannot support anything more than that,
     * which is why a thin month says so instead of pretending.
     *
     * @return array<string, mixed>
     */
    private function trend(string $salonId): array
    {
        $thisMonth = $this->averageBetween($salonId, Carbon::now()->startOfMonth(), Carbon::now());
        $lastMonth = $this->averageBetween(
            $salonId,
            Carbon::now()->subMonthNoOverflow()->startOfMonth(),
            Carbon::now()->subMonthNoOverflow()->endOfMonth()
        );

        // Two ratings do not make a trend, and telling an owner their salon is
        // "down 0.8" on that basis would be actively misleading.
        if ($thisMonth['count'] < 3 || $lastMonth['count'] < 3) {
            return [
                'comparable' => false,
                'this_month_average' => $thisMonth['average'],
                'this_month_count' => $thisMonth['count'],
                'label' => $thisMonth['count'] === 0
                    ? 'No ratings yet this month.'
                    : sprintf(
                        '%d %s this month, averaging %s. Too few to compare with last month yet.',
                        $thisMonth['count'],
                        $thisMonth['count'] === 1 ? 'rating' : 'ratings',
                        number_format($thisMonth['average'], 1)
                    ),
            ];
        }

        $change = round($thisMonth['average'] - $lastMonth['average'], 1);

        $label = match (true) {
            $change >= 0.3 => sprintf('Up from %s last month.', number_format($lastMonth['average'], 1)),
            $change <= -0.3 => sprintf('Down from %s last month.', number_format($lastMonth['average'], 1)),
            default => sprintf('About the same as last month (%s).', number_format($lastMonth['average'], 1)),
        };

        return [
            'comparable' => true,
            'this_month_average' => $thisMonth['average'],
            'this_month_count' => $thisMonth['count'],
            'last_month_average' => $lastMonth['average'],
            'change' => $change,
            'direction' => $change >= 0.3 ? 'up' : ($change <= -0.3 ? 'down' : 'flat'),
            'label' => $label,
        ];
    }

    /** @return array{average: float, count: int} */
    private function averageBetween(string $salonId, Carbon $from, Carbon $to): array
    {
        $stats = Review::where('salon_id', $salonId)
            ->whereBetween('created_at', [$from, $to])
            ->selectRaw('count(*) as total, avg(rating) as average')
            ->first();

        return [
            'average' => $stats->total > 0 ? round((float) $stats->average, 1) : 0.0,
            'count' => (int) $stats->total,
        ];
    }

    /**
     * Owners and their staff both see this. Staff are served by the same salon
     * the reviews are about, so there is nothing here they should not read.
     */
    private function denyUnlessOfTheSalon(Request $request, string $salonId)
    {
        $user = $request->user();

        if ($user->role === 'superadmin') {
            return null;
        }

        if ($user->role === 'admin'
            && Salon::where('id', $salonId)->where('admin_id', $user->id)->exists()) {
            return null;
        }

        if ($user->role === 'service_provider'
            && \App\Models\ServiceProvider::where('user_id', $user->id)
                ->where('salon_id', $salonId)->exists()) {
            return null;
        }

        return response()->json(['message' => 'You do not work at this salon.'], 403);
    }
}
