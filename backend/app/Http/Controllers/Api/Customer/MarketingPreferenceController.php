<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Models\MarketingConsent;
use App\Services\Marketing\AudienceBuilder;
use Illuminate\Http\Request;

/**
 * A customer's own say in whether salons may message them.
 *
 * This is the only place in the platform that can turn marketing *on* for
 * somebody. Salons cannot opt their customers in and neither can SuperAdmin —
 * which is the point. WhatsApp requires the permission to come from the person,
 * and a consent record the business created for itself is not consent.
 *
 * Turning it off is honoured everywhere and immediately: the send job rechecks
 * on its way out, so a campaign already in flight stops reaching anyone who
 * opted out while it was running.
 */
class MarketingPreferenceController extends Controller
{
    public function __construct(private AudienceBuilder $audiences)
    {
    }

    public function show(Request $request)
    {
        $user = $request->user();
        $phone = $this->audiences->normalisePhone($user->phone);

        $consent = $phone ? MarketingConsent::where('phone', $phone)->first() : null;

        return response()->json([
            'success' => true,
            'data' => [
                'opted_in' => $consent?->status === MarketingConsent::STATUS_IN,
                'decided' => $consent !== null,
                'updated_at' => $consent?->updated_at?->toIso8601String(),
            ],
        ]);
    }

    public function update(Request $request)
    {
        $data = $request->validate(['opted_in' => 'required|boolean']);

        $user = $request->user();
        $phone = $this->audiences->normalisePhone($user->phone);

        if (! $phone) {
            return response()->json([
                'success' => false,
                'message' => 'Add a valid phone number to your profile first.',
            ], 422);
        }

        if ($data['opted_in']) {
            // Deliberately re-opens an earlier opt-out: the model refuses to do
            // this on its own from a booking, but the person themselves asking
            // is exactly the case where it should be allowed.
            MarketingConsent::updateOrCreate(
                ['phone' => $phone],
                [
                    'user_id' => $user->id,
                    'status' => MarketingConsent::STATUS_IN,
                    'source' => MarketingConsent::SOURCE_BOOKING,
                    'opted_in_at' => now(),
                    'opted_out_at' => null,
                ]
            );
        } else {
            MarketingConsent::optOut($phone, MarketingConsent::SOURCE_BOOKING);
        }

        return response()->json([
            'success' => true,
            'message' => $data['opted_in']
                ? 'You will receive offers from salons you have visited.'
                : 'You will no longer receive marketing messages.',
        ]);
    }
}
