<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\City;
use App\Models\Combo;
use App\Models\Salon;
use App\Models\SalonWorkingHour;
use App\Models\Service;
use App\Models\ServiceProvider;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * The customer-facing salon profile. Everything a shopper needs to decide and
 * to build a cart, shaped so the app does not have to stitch it together.
 */
class SalonController extends Controller
{
    private const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

    public function show(Request $request, $id)
    {
        $salon = Salon::with(['city:id,name,state', 'currentSubscription'])->find($id);

        if (! $salon || $salon->status === 'rejected') {
            return response()->json(['message' => 'Salon not found.'], 404);
        }

        $services = $this->services($salon->id);
        $availability = $this->availabilityToday($salon);
        $bookable = $this->bookability($salon, $services);

        $isFavourited = false;
        if ($request->user()) {
            $isFavourited = $request->user()->favouriteSalons()->where('salon_id', $salon->id)->exists();
        }

        return response()->json([
            'salon' => [
                'id' => $salon->id,
                'name' => $salon->name,
                'slug' => $salon->slug,
                'description' => $salon->description,
                'address' => $salon->address,
                'pincode' => $salon->pincode,
                // phone_num is the owner's personal number. It is never sent to
                // a customer — the description carries the salon's own story.
                'map_url' => $salon->map_url,
                'latitude' => $salon->latitude,
                'longitude' => $salon->longitude,
                'city' => $salon->city?->name,
                'state' => $salon->city?->state,
                'gender_focus' => $salon->gender_focus,

                'cover_photo_url' => $salon->cover_photo_url,
                'gallery' => $this->gallery($salon),

                'rating' => $this->ratings($salon),

                'advance_required' => (bool) $salon->advance_required,
                'advance_refundable' => (bool) $salon->advance_refundable,
                'advance_percentage_default' => (float) $salon->advance_percentage_default,

                'is_favourited' => $isFavourited,

                'is_bookable' => $bookable['is_bookable'],
                'unavailable_reason' => $bookable['reason'],

                'is_open_now' => $availability['is_open_now'],
                'open_status_label' => $availability['label'],
                'today_hours' => $availability['today'],
                'working_hours' => $availability['week'],
                'upcoming_closures' => $this->upcomingClosures($salon->id),

                'categories' => $this->categories($services),
                'services' => $services,
                'combos' => $this->combos($salon->id),
                'team' => $this->team($salon->id),
            ],
        ]);
    }

    /**
     * Active, bookable services with their template detail and how many staff
     * can actually perform each one.
     */
    private function services(string $salonId): array
    {
        $rows = Service::with('template.category:id,name,icon_url')
            ->where('salon_id', $salonId)
            ->where('is_active', true)
            ->orderBy('display_order')
            ->get();

        $providerCounts = DB::table('provider_services')
            ->join('service_providers', 'service_providers.id', '=', 'provider_services.provider_id')
            ->where('service_providers.salon_id', $salonId)
            ->where('service_providers.is_active', true)
            ->whereNull('service_providers.deleted_at')
            ->groupBy('provider_services.service_id')
            ->pluck(DB::raw('count(*) as total'), 'provider_services.service_id')
            ->all();

        return $rows->map(fn (Service $service) => [
            'id' => $service->id,
            'name' => $service->template->name ?? 'Service',
            'description' => $service->description,
            'price' => (float) $service->price,
            'duration_minutes' => (int) ($service->template->estimated_duration_minutes ?? 30),
            'category_id' => $service->template->category_id ?? null,
            'category_name' => $service->template->category->name ?? 'Other',
            'gender_focus' => $service->gender_focus,
            'advance_percentage' => $service->advance_percentage !== null
                ? (float) $service->advance_percentage
                : null,
            'refundable_advance' => (bool) $service->will_refund_advance_if_cancelled,
            // Zero means nobody at this salon is trained for it — the app greys
            // it out rather than letting the customer hit a dead end at checkout.
            'provider_count' => (int) ($providerCounts[$service->id] ?? 0),
        ])->all();
    }

    /**
     * Category filter chips, derived from the services actually on offer.
     *
     * @param  array<int, array>  $services
     */
    private function categories(array $services): array
    {
        $categories = [];

        foreach ($services as $service) {
            $key = $service['category_id'] ?? 'other';

            $categories[$key] ??= [
                'id' => $service['category_id'],
                'name' => $service['category_name'],
                'service_count' => 0,
            ];

            $categories[$key]['service_count']++;
        }

        return array_values($categories);
    }

    /**
     * Combo packages, priced from their constituent services so the saving
     * against booking them separately is visible.
     */
    private function combos(string $salonId): array
    {
        return Combo::with('services.template:id,name,estimated_duration_minutes')
            ->where('salon_id', $salonId)
            ->where('is_active', true)
            ->get()
            ->map(function (Combo $combo) {
                $price = 0.0;
                $originalPrice = 0.0;
                $duration = 0;
                $lines = [];

                foreach ($combo->services as $service) {
                    $comboPrice = (float) ($service->pivot->combo_special_price ?? $service->price);
                    $price += $comboPrice;
                    $originalPrice += (float) $service->price;
                    $duration += (int) ($service->template->estimated_duration_minutes ?? 30);

                    $lines[] = [
                        'id' => $service->id,
                        'name' => $service->template->name ?? 'Service',
                        'price' => $comboPrice,
                        'original_price' => (float) $service->price,
                    ];
                }

                return [
                    'id' => $combo->id,
                    'name' => $combo->name,
                    'price' => round($price, 2),
                    'original_price' => round($originalPrice, 2),
                    'savings' => round(max($originalPrice - $price, 0), 2),
                    'duration_minutes' => $duration,
                    'advance_percentage' => (float) $combo->advance_percentage,
                    'refundable_advance' => (bool) $combo->will_refund_advance_if_cancelled,
                    'services' => $lines,
                ];
            })
            ->all();
    }

    private function team(string $salonId): array
    {
        return ServiceProvider::with('user:id,name')
            ->withCount('services')
            ->where('salon_id', $salonId)
            ->where('is_active', true)
            ->get()
            ->map(fn (ServiceProvider $provider) => [
                'id' => $provider->id,
                'name' => $provider->user->name ?? 'Staff',
                'specialization' => $provider->specialization,
                'service_count' => $provider->services_count,
            ])
            ->all();
    }

    private function gallery(Salon $salon): array
    {
        $media = DB::table('salon_media')
            ->where('salon_id', $salon->id)
            ->where('media_type', 'image')
            ->orderByDesc('is_cover')
            ->orderBy('sort_order')
            ->get(['file_url', 'thumbnail_url', 'alt_text', 'is_cover']);

        $gallery = $media->map(fn ($item) => [
            'url' => $item->file_url,
            'thumbnail_url' => $item->thumbnail_url,
            'alt_text' => $item->alt_text,
        ])->all();

        // Salons that only ever set a cover photo still get a one-image gallery.
        if (empty($gallery) && $salon->cover_photo_url) {
            $gallery[] = [
                'url' => $salon->cover_photo_url,
                'thumbnail_url' => null,
                'alt_text' => $salon->name,
            ];
        }

        return $gallery;
    }

    /**
     * Ratings computed from the reviews themselves; salons.avg_rating is only a
     * denormalised snapshot, so it is the fallback rather than the source.
     */
    private function ratings(Salon $salon): array
    {
        $reviews = DB::table('reviews')
            ->join('users', 'users.id', '=', 'reviews.customer_id')
            ->where('reviews.salon_id', $salon->id)
            ->get(['reviews.id', 'reviews.rating', 'reviews.comment', 'users.name as customer_name']);

        $breakdown = [];
        for ($star = 5; $star >= 1; $star--) {
            $breakdown[$star] = $reviews->where('rating', $star)->count();
        }

        return [
            'average' => $reviews->isNotEmpty()
                ? round($reviews->avg('rating'), 1)
                : round((float) $salon->avg_rating, 1),
            'count' => $reviews->isNotEmpty() ? $reviews->count() : (int) $salon->review_count,
            'breakdown' => $breakdown,
            'recent' => $reviews->filter(fn ($r) => filled($r->comment))
                ->take(5)
                ->map(fn ($r) => [
                    'rating' => (int) $r->rating,
                    'comment' => $r->comment,
                    'customer_name' => $r->customer_name,
                ])
                ->values()
                ->all(),
        ];
    }

    /**
     * Today's opening state plus the whole week, for the hours panel.
     */
    private function availabilityToday(Salon $salon): array
    {
        $hours = SalonWorkingHour::where('salon_id', $salon->id)->get()->keyBy('day_of_week');
        $today = now();
        $todayRow = $hours->get($today->dayOfWeek);

        $week = [];
        for ($day = 0; $day <= 6; $day++) {
            $row = $hours->get($day);
            $week[] = [
                'day_of_week' => $day,
                'day_name' => self::DAY_NAMES[$day],
                'is_closed' => $row ? (bool) $row->is_closed : true,
                'open_time' => $row && ! $row->is_closed ? substr((string) $row->open_time, 0, 5) : null,
                'close_time' => $row && ! $row->is_closed ? substr((string) $row->close_time, 0, 5) : null,
                'is_today' => $day === $today->dayOfWeek,
            ];
        }

        $closedToday = DB::table('salon_closures')
            ->where('salon_id', $salon->id)
            ->whereDate('closed_date', $today->format('Y-m-d'))
            ->whereNull('reopened_at')
            ->first();

        if ($closedToday) {
            return [
                'is_open_now' => false,
                'label' => 'Closed today' . ($closedToday->reason ? ' · ' . $closedToday->reason : ''),
                'today' => $week[$today->dayOfWeek],
                'week' => $week,
            ];
        }

        if (! $todayRow || $todayRow->is_closed || ! $todayRow->open_time || ! $todayRow->close_time) {
            return [
                'is_open_now' => false,
                'label' => 'Closed today',
                'today' => $week[$today->dayOfWeek],
                'week' => $week,
            ];
        }

        $open = Carbon::parse($today->format('Y-m-d') . ' ' . $todayRow->open_time);
        $close = Carbon::parse($today->format('Y-m-d') . ' ' . $todayRow->close_time);
        $isOpen = $today->betweenIncluded($open, $close);

        return [
            'is_open_now' => $isOpen,
            'label' => $isOpen
                ? 'Open now · closes ' . $close->format('g:i A')
                : ($today->lessThan($open)
                    ? 'Opens at ' . $open->format('g:i A')
                    : 'Closed · opens ' . $open->format('g:i A') . ' tomorrow'),
            'today' => $week[$today->dayOfWeek],
            'week' => $week,
        ];
    }

    /**
     * Announced closures in the next month, so a customer does not book into a
     * day the salon has already blocked off.
     */
    private function upcomingClosures(string $salonId): array
    {
        return DB::table('salon_closures')
            ->where('salon_id', $salonId)
            ->whereNull('reopened_at')
            ->whereDate('closed_date', '>=', now()->format('Y-m-d'))
            ->whereDate('closed_date', '<=', now()->addDays(30)->format('Y-m-d'))
            ->orderBy('closed_date')
            ->get(['closed_date', 'reason'])
            ->map(fn ($row) => [
                'date' => Carbon::parse($row->closed_date)->format('Y-m-d'),
                'label' => Carbon::parse($row->closed_date)->format('D, M j'),
                'reason' => $row->reason,
            ])
            ->all();
    }

    /**
     * The salon directory the customer app browses.
     *
     * Explore used to read the SuperAdmin directory, which knows nothing about
     * subscriptions — so a salon whose plan had lapsed still looked open for
     * business. Serviceability is decided here by the same rule the detail page
     * uses, and unserviceable salons are marked rather than hidden so a
     * returning customer can still find one they know.
     *
     * Results are scoped to one city. A customer in Pune scrolling past salons
     * in Bangalore is browsing a database, not a marketplace — nothing in that
     * list is bookable by them. The city is resolved here rather than demanded
     * from the caller, so an older client that sends nothing still gets a
     * sensible list instead of an error.
     */
    public function index(Request $request)
    {
        $access = app(\App\Services\SalonAccessService::class);

        // One sweep, rather than once per salon.
        $access->expireStale();

        $city = $this->resolveCity($request);

        $query = Salon::with(['currentSubscription'])
            ->where('status', 'active');

        if ($request->filled('search')) {
            $search = $request->search;
            $query->where(fn ($q) => $q->where('name', 'like', "%{$search}%")
                ->orWhere('address', 'like', "%{$search}%"));
        }

        if ($city) {
            $query->where('city_id', $city->id);
        }

        if ($request->filled('gender')) {
            $gender = strtolower($request->gender);
            if ($gender === 'men') {
                $query->whereIn('gender_focus', ['Unisex', 'Men Only']);
            } elseif ($gender === 'women') {
                $query->whereIn('gender_focus', ['Unisex', 'Women Only']);
            }
        }

        if ($request->filled('category_id')) {
            $categoryId = $request->category_id;
            $query->whereHas('services.template', function ($q) use ($categoryId) {
                $q->where('category_id', $categoryId);
            });
        }

        // Distance decides the order when the app knows where the customer is.
        // Within one city that is the only ordering that means anything — a
        // salon three streets away and one an hour across town are not
        // equivalent just because they share a postcode.
        $geo = app(\App\Services\GeoService::class);
        $hasPosition = $geo->isValid($request->lat, $request->lng);

        if ($hasPosition) {
            $geo->orderByDistance($query, (float) $request->lat, (float) $request->lng);
        } else {
            $query->orderByDesc('avg_rating')->orderBy('name');
        }

        $salons = $query->get();

        $rows = $this->present($salons, $access);

        $suggestedRows = collect();
        $alternativeCity = null;

        // An empty list is a dead end, so it never ships on its own. A failed
        // search falls back to what else is in this city; a city with nothing
        // in it at all falls back to the nearest market that does.
        if ($rows->isEmpty()) {
            if ($request->filled('search') || $request->filled('category_id')) {
                $suggestedRows = $this->present(
                    Salon::with(['currentSubscription'])
                        ->where('status', 'active')
                        ->when($city, fn ($q) => $q->where('city_id', $city->id))
                        ->orderByDesc('avg_rating')
                        ->limit(5)
                        ->get(),
                    $access
                );
            }

            // Still nothing — this city has no salons worth showing. Point at
            // the busiest one that does, so the screen has somewhere to go.
            if ($suggestedRows->isEmpty()) {
                $alternativeCity = City::where('is_active', true)
                    ->when($city, fn ($q) => $q->where('id', '!=', $city->id))
                    ->serviceable()
                    ->withOpenSalonCount()
                    ->orderByDesc('salon_count')
                    ->first();

                if ($alternativeCity) {
                    $suggestedRows = $this->present(
                        Salon::with(['currentSubscription'])
                            ->where('status', 'active')
                            ->where('city_id', $alternativeCity->id)
                            ->orderByDesc('avg_rating')
                            ->limit(5)
                            ->get(),
                        $access
                    );
                }
            }
        }

        // Salons that can be booked come first; the rest stay findable below.
        return response()->json([
            'salons' => $rows->sortByDesc('is_serviceable')->values(),
            'suggested_salons' => $suggestedRows->sortByDesc('is_serviceable')->values(),
            // The app shows which market it is displaying, because a customer
            // seeing no salons must be able to tell "none here" from "broken".
            'sorted_by' => $hasPosition ? 'distance' : 'rating',
            'city' => $city ? [
                'id' => $city->id,
                'name' => $city->name,
                'state' => $city->state,
            ] : null,
            'suggested_city' => $alternativeCity ? [
                'id' => $alternativeCity->id,
                'name' => $alternativeCity->name,
                'state' => $alternativeCity->state,
                'salon_count' => (int) $alternativeCity->salon_count,
            ] : null,
        ]);
    }

    /**
     * Which city's salons to show.
     *
     * In order of how much the platform should trust it: what the app asked
     * for, then the customer's saved city, then the busiest market so a first
     * launch has something in it. Null only when the platform serves nowhere,
     * in which case the unfiltered list is still better than an error.
     */
    private function resolveCity(Request $request): ?City
    {
        if ($request->filled('city_id')) {
            $chosen = City::find($request->city_id);

            if ($chosen) {
                return $chosen;
            }
        }

        // The directory is a public route, so the request has no resolved user
        // even when a signed-in customer sends their token. Ask the guard
        // directly, otherwise a returning customer silently loses their city.
        $saved = auth('sanctum')->user()?->city;

        if ($saved) {
            return $saved;
        }

        // Nothing chosen and nothing saved, but the app told us where they are.
        // Using it beats the blind default: a customer standing in Mumbai
        // should not be shown the busiest market instead of their own.
        $geo = app(\App\Services\GeoService::class);

        if ($geo->isValid($request->lat, $request->lng)) {
            $market = $geo->marketFor((float) $request->lat, (float) $request->lng);

            if ($market['city']) {
                return $market['city'];
            }
        }

        return City::where('is_active', true)
            ->serviceable()
            ->withOpenSalonCount()
            ->orderByDesc('salon_count')
            ->first();
    }

    /** The row shape the directory returns, used for results and suggestions. */
    private function present($salons, $access)
    {
        return $salons->map(function (Salon $salon) use ($access) {
            $status = $access->status($salon);

            return [
                'id' => $salon->id,
                'name' => $salon->name,
                'address' => $salon->address,
                'cover_photo_url' => $salon->cover_photo_url,
                'avg_rating' => (float) $salon->avg_rating,
                'review_count' => (int) $salon->review_count,
                'is_serviceable' => $status['is_active'],
                'unavailable_reason' => $status['message'],
                // Null when the customer shared no position, or the salon has
                // not been placed on the map yet.
                'distance_km' => isset($salon->distance_km)
                    ? round((float) $salon->distance_km, 1)
                    : null,
                // A salon sitting at its city centre has not pinned itself, so
                // the distance is indicative. The app says "about" for these
                // rather than presenting a guess as a measurement.
                'distance_is_approximate' => $salon->location_source === 'city_centre',
            ];
        });
    }

    /**
     * Whether the salon can take bookings at all. An expired or missing
     * subscription makes the page a "temporarily unavailable" state rather than
     * hiding the salon outright.
     *
     * @param  array<int, array>  $services
     * @return array{is_bookable: bool, reason: ?string}
     */
    private function bookability(Salon $salon, array $services): array
    {
        if ($salon->status === 'suspended') {
            return ['is_bookable' => false, 'reason' => 'This salon is temporarily unavailable.'];
        }

        if ($salon->status !== 'active') {
            return ['is_bookable' => false, 'reason' => 'This salon is not accepting online bookings yet.'];
        }

        $subscription = $salon->currentSubscription;

        if (! $subscription || Carbon::parse($subscription->end_date)->isPast()) {
            return [
                'is_bookable' => false,
                'reason' => 'This salon is temporarily unavailable for online booking.',
            ];
        }

        if (empty($services)) {
            return ['is_bookable' => false, 'reason' => 'This salon has not published any services yet.'];
        }

        return ['is_bookable' => true, 'reason' => null];
    }
}
