<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\Salon;
use App\Services\BankDetailsService;
use App\Services\SalonAccessService;
use Illuminate\Http\Request;

/**
 * The salon owner's own bank details, for receiving settlements.
 *
 * Only the owner of this salon. Staff and other salons' owners are refused
 * however they reach the endpoint. The full account number is never sent back
 * — the app shows its last four digits.
 */
class BankDetailsController extends Controller
{
    public function __construct(
        private BankDetailsService $bank,
        private SalonAccessService $access,
    ) {
    }

    public function show(Request $request, string $salonId)
    {
        $salon = $this->ownedSalon($request, $salonId);

        if (! $salon) {
            return response()->json(['message' => 'You can only see bank details for your own salon.'], 403);
        }

        return response()->json($this->payload($salon));
    }

    public function update(Request $request, string $salonId)
    {
        $salon = $this->ownedSalon($request, $salonId);

        if (! $salon) {
            return response()->json(['message' => 'You can only change bank details for your own salon.'], 403);
        }

        $clean = $this->bank->validate($request->only(BankDetailsService::FIELDS), $salon);
        $this->bank->apply($salon, $clean, $request->user());

        return response()->json(['message' => 'Bank details saved.'] + $this->payload($salon->fresh()));
    }

    /**
     * "Same as my other salon": copy the account from another salon the same
     * owner runs. Done here rather than in the app so the full account number
     * never has to travel to the phone and back.
     */
    public function copy(Request $request, string $salonId)
    {
        $salon = $this->ownedSalon($request, $salonId);

        if (! $salon) {
            return response()->json(['message' => 'You can only change bank details for your own salon.'], 403);
        }

        $request->validate(['from_salon_id' => 'required|string']);

        $source = $this->ownedSalon($request, (string) $request->input('from_salon_id'));

        if (! $source || $source->id === $salon->id) {
            return response()->json(['message' => 'Choose another of your own salons to copy from.'], 422);
        }

        if (! $this->bank->hasRequired($source)) {
            return response()->json([
                'message' => "{$source->name} does not have complete bank details to copy.",
            ], 422);
        }

        $this->bank->apply($salon, $this->bank->valuesOf($source), $request->user());

        return response()->json(
            ['message' => "Bank details copied from {$source->name}."] + $this->payload($salon->fresh())
        );
    }

    /**
     * The owner's salons with complete bank details, masked — offered as
     * "Same as my other salon" while registering a new branch, before that
     * branch has an id of its own.
     */
    public function saved(Request $request)
    {
        $user = $request->user();

        if (! $user || $user->role !== 'admin') {
            return response()->json(['salons' => []]);
        }

        return response()->json(['salons' => $this->bank->copyableFor($user->id)]);
    }

    /**
     * The details, plus whether the Home tab should nag: a live plan and the
     * transfer fields still missing. [other_salons] lists the owner's other
     * salons whose account can be copied here, masked like this one.
     */
    private function payload(Salon $salon): array
    {
        $hasRequired = $this->bank->hasRequired($salon);
        $planActive = (bool) ($this->access->status($salon)['is_active'] ?? false);

        return [
            'bank_details' => $this->bank->present($salon),
            'show_missing_warning' => $planActive && ! $hasRequired,
            'other_salons' => $this->bank->copyableFor($salon->admin_id, $salon->id),
        ];
    }

    private function ownedSalon(Request $request, string $salonId): ?Salon
    {
        $user = $request->user();

        if (! $user || $user->role !== 'admin') {
            return null;
        }

        return Salon::where('id', $salonId)->where('admin_id', $user->id)->first();
    }
}
