<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\Salon;
use Illuminate\Http\Request;
use App\Services\SalonAccessService;

class FavouriteController extends Controller
{
    /**
     * Get the customer's favourited salons.
     */
    public function index(Request $request, SalonAccessService $access)
    {
        $user = $request->user();

        $favouriteSalons = $user->favouriteSalons()->with(['currentSubscription'])->orderBy('favourite_salons.created_at', 'desc')->get();

        $rows = $favouriteSalons->map(function (Salon $salon) use ($access) {
            $status = $access->status($salon);

            return [
                'id' => $salon->id,
                'name' => $salon->name,
                'address' => $salon->address,
                'cover_photo_url' => $salon->cover_photo_url,
                'is_serviceable' => $status['is_active'],
                'unavailable_reason' => $status['message'],
                'rating' => [
                    'average' => round((float) $salon->avg_rating, 1),
                    'count' => (int) $salon->review_count,
                ],
            ];
        });

        // Favourites remain in the list even if the plan expires, so the customer doesn't lose them.
        return response()->json([
            'favourites' => $rows,
        ]);
    }

    /**
     * Toggle a salon in the customer's favourites.
     */
    public function toggle(Request $request, $salon_id)
    {
        $user = $request->user();

        $salon = Salon::findOrFail($salon_id);

        $isFavourited = $user->favouriteSalons()->where('salon_id', $salon->id)->exists();

        if ($isFavourited) {
            $user->favouriteSalons()->detach($salon->id);
            $message = 'Salon removed from favourites.';
            $status = false;
        } else {
            $user->favouriteSalons()->attach($salon->id);
            $message = 'Salon added to favourites.';
            $status = true;
        }

        return response()->json([
            'message' => $message,
            'is_favourited' => $status,
        ]);
    }
}
