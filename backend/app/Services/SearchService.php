<?php

namespace App\Services;

use App\Models\Salon;
use App\Models\ServiceCategory;
use App\Models\ServiceTemplate;
use Illuminate\Support\Facades\DB;

/**
 * One search box over services, salons and categories.
 *
 * Customers do not think in the app's nouns. Someone wanting a haircut types
 * "haircut", not the name of a salon, and the old search only looked at salon
 * names and addresses — so the commonest search on a salon app returned
 * nothing. This matches what people actually type against what they are
 * actually looking for, and answers with the service *and* the salon offering
 * it, the way a food app answers with the dish and the restaurant.
 *
 * Typos are handled in PHP rather than in SQL. Neither SQLite nor MySQL offers
 * a usable fuzzy operator out of the box, and the thing being matched against —
 * the master service catalogue — is small enough to score in memory in well
 * under a millisecond. Scoring here also means one scale for every kind of
 * result, so a service and a salon can be ranked against each other honestly.
 */
class SearchService
{
    /** Below this a match is worse than showing nothing. */
    private const THRESHOLD = 55;

    /**
     * How well `$needle` matches `$haystack`, from 0 to 100.
     *
     * The ladder runs from certainty down to guesswork: exact, prefix,
     * substring, word-prefix, then the three kinds of near-miss people actually
     * make — a slip of the fingers, a slip in one word of several, and a word
     * spelled how it sounds.
     */
    public function score(string $needle, string $haystack): int
    {
        $needle = $this->normalise($needle);
        $hay = $this->normalise($haystack);

        if ($needle === '' || $hay === '') {
            return 0;
        }

        if ($needle === $hay) {
            return 100;
        }

        if (str_starts_with($hay, $needle)) {
            return 92;
        }

        if (str_contains($hay, $needle)) {
            return 84;
        }

        $words = preg_split('/\s+/', $hay) ?: [];

        foreach ($words as $word) {
            if ($word !== '' && str_starts_with($word, $needle)) {
                return 80;
            }
        }

        // What counts as a typo rather than a different word. The budget grows
        // with the length of what was typed: "hiar" for "hair" is one slip in
        // four letters, but allowing three slips in four would match anything.
        $budget = max(1, (int) floor(mb_strlen($needle) / 4));

        $whole = $this->editDistance($needle, $hay);
        if ($whole <= $budget) {
            return 78 - $whole * 5;
        }

        // The typo is in one word of a longer name: "haircutt" against
        // "Men's Haircut".
        $best = 0;
        foreach ($words as $word) {
            if ($word === '') {
                continue;
            }

            $distance = $this->editDistance($needle, $word);
            if ($distance <= $budget) {
                $best = max($best, 74 - $distance * 5);
            }
        }
        if ($best > 0) {
            return $best;
        }

        // Spelled how it sounds — "kolor" for "colour", "fasial" for "facial".
        // Only trusted for words long enough that a shared sound is unlikely to
        // be coincidence.
        if (mb_strlen($needle) >= 4) {
            $sound = metaphone($needle);

            if ($sound !== '' && $sound === metaphone($hay)) {
                return 66;
            }

            foreach ($words as $word) {
                if (mb_strlen($word) >= 4 && $sound !== '' && $sound === metaphone($word)) {
                    return 62;
                }
            }
        }

        // Last resort: broadly similar strings.
        similar_text($needle, $hay, $percent);
        if ($percent >= 72) {
            return (int) round($percent * 0.72);
        }

        return 0;
    }

    /**
     * Search everything a customer might mean.
     *
     * @return array<string, mixed>
     */
    public function search(string $query, ?string $cityId, int $limit = 20): array
    {
        $query = trim($query);

        if (mb_strlen($query) < 2) {
            return ['services' => [], 'salons' => [], 'categories' => [], 'did_you_mean' => null];
        }

        $templates = $this->matchTemplates($query);
        $categories = $this->matchCategories($query);

        return [
            'services' => $this->servicesFor($templates, $cityId, $limit),
            'salons' => $this->matchSalons($query, $cityId, $limit),
            'categories' => $categories,
            // Only offered when nothing matched cleanly — a correction shown
            // above results the customer can already see is just noise.
            'did_you_mean' => $this->didYouMean($query, $templates),
        ];
    }

    /**
     * Master services whose name the query is reaching for.
     *
     * @return array<string, int> template id => score
     */
    private function matchTemplates(string $query): array
    {
        $scored = [];

        foreach (ServiceTemplate::where('is_active', true)->get(['id', 'name']) as $template) {
            $score = $this->score($query, $template->name);

            if ($score >= self::THRESHOLD) {
                $scored[$template->id] = $score;
            }
        }

        arsort($scored);

        return $scored;
    }

    /** @return array<int, array<string, mixed>> */
    private function matchCategories(string $query): array
    {
        $found = [];

        foreach (ServiceCategory::where('is_active', true)->get(['id', 'name', 'icon_url']) as $category) {
            $score = $this->score($query, $category->name);

            if ($score >= self::THRESHOLD) {
                $found[] = [
                    'id' => $category->id,
                    'name' => $category->name,
                    'icon_url' => $category->publicIconUrl(),
                    'score' => $score,
                ];
            }
        }

        usort($found, fn ($a, $b) => $b['score'] <=> $a['score']);

        return array_slice($found, 0, 6);
    }

    /**
     * The matched services as a customer sees them: the service, its price, and
     * the salon that will actually perform it.
     *
     * @param  array<string, int>  $templates
     * @return array<int, array<string, mixed>>
     */
    private function servicesFor(array $templates, ?string $cityId, int $limit): array
    {
        if ($templates === []) {
            return [];
        }

        $rows = DB::table('services as sv')
            ->join('salons as s', 's.id', '=', 'sv.salon_id')
            ->join('service_templates as t', 't.id', '=', 'sv.template_id')
            ->leftJoin('service_categories as c', 'c.id', '=', 't.category_id')
            ->leftJoin('sub_areas as a', 'a.id', '=', 's.sub_area_id')
            ->whereIn('sv.template_id', array_keys($templates))
            ->where('sv.is_active', true)
            ->whereNull('sv.deleted_at')
            ->where('s.status', 'active')
            ->whereNull('s.deleted_at')
            ->when($cityId, fn ($q) => $q->where('s.city_id', $cityId))
            ->select([
                'sv.id as service_id',
                'sv.price',
                'sv.template_id',
                't.name as service_name',
                't.estimated_duration_minutes as duration',
                'c.name as category_name',
                's.id as salon_id',
                's.name as salon_name',
                's.slug as salon_slug',
                's.avg_rating',
                's.review_count',
                'a.name as area_name',
            ])
            ->limit(200)
            ->get();

        $results = $rows->map(function ($row) use ($templates) {
            return [
                'service_id' => $row->service_id,
                'name' => $row->service_name,
                'category' => $row->category_name,
                'price' => (float) $row->price,
                'duration_minutes' => (int) $row->duration,
                'match_score' => $templates[$row->template_id] ?? 0,
                'salon' => [
                    'id' => $row->salon_id,
                    'name' => $row->salon_name,
                    'slug' => $row->salon_slug,
                    'area' => $row->area_name,
                    'avg_rating' => round((float) $row->avg_rating, 1),
                    'review_count' => (int) $row->review_count,
                ],
            ];
        })->sort(function ($a, $b) {
            // Closest match first; among equally good matches, the better-rated
            // salon, then the cheaper one — the order a customer would pick in.
            return [$b['match_score'], $b['salon']['avg_rating'], -$a['price']]
                <=> [$a['match_score'], $a['salon']['avg_rating'], -$b['price']];
        })->take($limit)->values();

        return $results->all();
    }

    /** @return array<int, array<string, mixed>> */
    private function matchSalons(string $query, ?string $cityId, int $limit): array
    {
        $salons = Salon::query()
            ->where('status', 'active')
            ->when($cityId, fn ($q) => $q->where('city_id', $cityId))
            ->with('subArea:id,name')
            ->get(['id', 'name', 'slug', 'address', 'avg_rating', 'review_count', 'sub_area_id']);

        $scored = [];

        foreach ($salons as $salon) {
            // A salon matches on its name or on where it is — "Kothrud" should
            // find the salons in Kothrud.
            $score = max(
                $this->score($query, $salon->name),
                $this->score($query, $salon->subArea?->name ?? '') - 6,
            );

            // Addresses are long and noisy, so only a literal hit counts.
            if ($score < self::THRESHOLD && stripos($salon->address ?? '', $query) !== false) {
                $score = 70;
            }

            if ($score >= self::THRESHOLD) {
                $scored[] = [
                    'id' => $salon->id,
                    'name' => $salon->name,
                    'slug' => $salon->slug,
                    'area' => $salon->subArea?->name,
                    'avg_rating' => round((float) $salon->avg_rating, 1),
                    'review_count' => (int) $salon->review_count,
                    'match_score' => $score,
                ];
            }
        }

        usort($scored, fn ($a, $b) => [$b['match_score'], $b['avg_rating']] <=> [$a['match_score'], $a['avg_rating']]);

        return array_slice($scored, 0, $limit);
    }

    /**
     * The spelling the customer probably meant.
     *
     * Offered only when the best match was a near-miss rather than a clean hit,
     * so it appears when it is useful and stays quiet when it is not.
     *
     * @param  array<string, int>  $templates
     */
    private function didYouMean(string $query, array $templates): ?string
    {
        if ($templates === []) {
            return null;
        }

        $best = reset($templates);

        // A clean match needs no correcting.
        if ($best >= 84) {
            return null;
        }

        $name = ServiceTemplate::whereKey(array_key_first($templates))->value('name');

        return $name && $this->normalise($name) !== $this->normalise($query) ? $name : null;
    }

    /**
     * Edit distance that treats a swap of two neighbouring letters as one
     * mistake (Damerau-Levenshtein).
     *
     * PHP's built-in levenshtein() charges two for a transposition, which reads
     * as two separate typos and pushes the commonest kind of slip — "facail"
     * for "facial", "recieve" for "receive" — outside any sane budget. Fingers
     * land in the wrong order far more often than they insert and delete, so
     * the distinction is worth the extra few lines.
     */
    private function editDistance(string $a, string $b): int
    {
        $lenA = mb_strlen($a);
        $lenB = mb_strlen($b);

        if ($lenA === 0) {
            return $lenB;
        }
        if ($lenB === 0) {
            return $lenA;
        }

        $charsA = preg_split('//u', $a, -1, PREG_SPLIT_NO_EMPTY) ?: [];
        $charsB = preg_split('//u', $b, -1, PREG_SPLIT_NO_EMPTY) ?: [];

        // Full matrix rather than two rolling rows, because a transposition
        // needs to look back two positions in both directions.
        $d = [];
        for ($i = 0; $i <= $lenA; $i++) {
            $d[$i] = [$i];
        }
        for ($j = 0; $j <= $lenB; $j++) {
            $d[0][$j] = $j;
        }

        for ($i = 1; $i <= $lenA; $i++) {
            for ($j = 1; $j <= $lenB; $j++) {
                $cost = $charsA[$i - 1] === $charsB[$j - 1] ? 0 : 1;

                $d[$i][$j] = min(
                    $d[$i - 1][$j] + 1,        // deletion
                    $d[$i][$j - 1] + 1,        // insertion
                    $d[$i - 1][$j - 1] + $cost // substitution
                );

                if (
                    $i > 1 && $j > 1
                    && $charsA[$i - 1] === $charsB[$j - 2]
                    && $charsA[$i - 2] === $charsB[$j - 1]
                ) {
                    $d[$i][$j] = min($d[$i][$j], $d[$i - 2][$j - 2] + 1);
                }
            }
        }

        return $d[$lenA][$lenB];
    }

    private function normalise(string $value): string
    {
        // Apostrophes and punctuation are noise here: nobody types the
        // apostrophe in "Men's Haircut".
        $value = mb_strtolower(trim($value));
        $value = preg_replace('/[^\p{L}\p{N}\s]+/u', '', $value) ?? $value;

        return trim(preg_replace('/\s+/', ' ', $value) ?? $value);
    }
}
