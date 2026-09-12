<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Salon;
use App\Services\SalonAccessService;
use App\Services\SalonLinkService;
use Illuminate\Http\Request;

/**
 * What a scanned QR code resolves to.
 *
 * Deliberately unauthenticated and deliberately thin. Whoever scans a poster in
 * a salon window has no account, no app and no patience — this exists so the
 * page they land on can name the salon and show its photo before it asks them
 * to install anything.
 *
 * Addressed by slug because that is what is printed on the wall. The slug is
 * already unique and already stable.
 */
class PublicSalonController extends Controller
{
    public function __construct(private SalonLinkService $links)
    {
    }

    public function show(string $slug, SalonAccessService $access)
    {
        $salon = Salon::with(['city:id,name,state'])
            ->where('slug', $slug)
            ->whereIn('status', ['active', 'suspended'])
            ->first();

        if (! $salon) {
            return response()->json([
                'success' => false,
                'message' => 'We could not find that salon.',
            ], 404);
        }

        $status = $access->status($salon);

        return response()->json([
            'success' => true,
            'salon' => [
                'id' => $salon->id,
                'slug' => $salon->slug,
                'name' => $salon->name,
                'description' => $salon->description,
                'address' => $salon->address,
                'city' => $salon->city?->name,
                'state' => $salon->city?->state,
                'cover_photo_url' => $salon->cover_photo_url,
                'avg_rating' => (float) $salon->avg_rating,
                'review_count' => (int) $salon->review_count,
                // A salon whose plan has lapsed still gets a page — somebody is
                // standing in front of it — but the page does not promise a
                // booking it cannot take.
                'is_bookable' => $status['is_active'],
            ],
            'deep_link' => $this->links->deepLink($salon),
            'android_intent_link' => $this->links->androidIntentLink($salon),
            'app_links' => $this->links->appLinks(),
        ]);
    }

    /** Where to send someone who wants the app, wherever they are coming from. */
    public function appLinks()
    {
        return response()->json([
            'success' => true,
            'app_links' => $this->links->appLinks(),
        ]);
    }
}
