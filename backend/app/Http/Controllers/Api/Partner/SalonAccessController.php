<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Services\SalonAccessService;
use Illuminate\Http\Request;

/**
 * Can this salon be worked in right now?
 *
 * Both roles ask, and both get an answer shaped for what they can do about it:
 * an owner can renew, a staff member can only pick up the phone.
 */
class SalonAccessController extends Controller
{
    public function __construct(private SalonAccessService $access)
    {
    }

    public function show(Request $request, $salonId)
    {
        $user = $request->user();
        $salon = Salon::with('admin:id,name,phone')->find($salonId);

        if (! $salon) {
            return response()->json(['message' => 'Salon not found.'], 404);
        }

        $isOwner = $user->role === 'admin' && $salon->admin_id === $user->id;
        $isStaff = $user->role === 'service_provider'
            && ServiceProvider::where('user_id', $user->id)->where('salon_id', $salon->id)->exists();

        if (! $isOwner && ! $isStaff && $user->role !== 'superadmin') {
            return response()->json(['message' => 'You do not work at this salon.'], 403);
        }

        $payload = $this->access->partnerPayload($salon);

        return response()->json($payload + [
            // Only the owner can renew; staff are shown who to chase instead.
            'can_renew' => $isOwner || $user->role === 'superadmin',
            'viewer_role' => $user->role,
        ]);
    }
}
