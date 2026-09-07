<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\WalletScheme;
use App\Models\WalletTransaction;
use App\Services\WalletService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

/**
 * Reward ladders.
 *
 * A ladder is a set of contiguous bands — "1 to 250", "251 to 350", "351
 * upwards" — each worth more than the one before. The rungs are validated as a
 * whole because a ladder with a gap or an overlap would silently stop paying
 * salons at the seam.
 */
class WalletSchemeController extends Controller
{
    public function __construct(private WalletService $wallet)
    {
    }

    public function index()
    {
        $schemes = WalletScheme::with('tiers')
            ->withCount('tiers')
            ->orderByDesc('created_at')
            ->get();

        $inForce = $this->wallet->schemeInForceOn();

        return response()->json([
            'success' => true,
            'coin_value_inr' => $this->wallet->coinValue(),
            'scheme_in_force_id' => $inForce?->id,
            'award_modes' => WalletScheme::MODES,
            'schemes' => $schemes->map(fn (WalletScheme $scheme) => $this->present($scheme)),
        ]);
    }

    public function show($id)
    {
        $scheme = WalletScheme::with('tiers')->findOrFail($id);

        return response()->json(['success' => true, 'scheme' => $this->present($scheme)]);
    }

    public function store(Request $request)
    {
        $data = $this->validated($request);

        if ($data instanceof \Illuminate\Http\JsonResponse) {
            return $data;
        }

        $scheme = DB::transaction(function () use ($data, $request) {
            $scheme = WalletScheme::create([
                'name' => $data['name'],
                'description' => $data['description'] ?? null,
                'award_mode' => $data['award_mode'] ?? WalletScheme::MODE_PER_APPOINTMENT,
                'is_active' => $data['is_active'] ?? true,
                'starts_on' => $data['starts_on'] ?? null,
                'ends_on' => $data['ends_on'] ?? null,
                'created_by' => $request->user()->id,
            ]);

            $this->syncTiers($scheme, $data['tiers']);

            return $scheme;
        });

        return response()->json([
            'success' => true,
            'scheme' => $this->present($scheme->fresh('tiers')),
        ], 201);
    }

    public function update(Request $request, $id)
    {
        $scheme = WalletScheme::findOrFail($id);
        $data = $this->validated($request);

        if ($data instanceof \Illuminate\Http\JsonResponse) {
            return $data;
        }

        DB::transaction(function () use ($scheme, $data) {
            $scheme->update([
                'name' => $data['name'],
                'description' => $data['description'] ?? null,
                'award_mode' => $data['award_mode'] ?? $scheme->award_mode,
                'is_active' => $data['is_active'] ?? $scheme->is_active,
                'starts_on' => $data['starts_on'] ?? null,
                'ends_on' => $data['ends_on'] ?? null,
            ]);

            // Rungs already referenced by an earned transaction are kept — the
            // history has to keep explaining itself — so replacing them is only
            // safe when nothing has been awarded against this scheme yet.
            $this->syncTiers($scheme, $data['tiers']);
        });

        return response()->json([
            'success' => true,
            'scheme' => $this->present($scheme->fresh('tiers')),
        ]);
    }

    /**
     * Retire a ladder. A scheme that has already paid coins is deactivated
     * rather than deleted, so the transactions that point at its rungs still
     * resolve.
     */
    public function destroy($id)
    {
        $scheme = WalletScheme::with('tiers')->findOrFail($id);

        if ($this->hasAwards($scheme)) {
            $scheme->update(['is_active' => false, 'ends_on' => now()->toDateString()]);

            return response()->json([
                'success' => true,
                'deactivated' => true,
                'message' => 'This scheme has already awarded coins, so it was closed rather than deleted.',
            ]);
        }

        DB::transaction(function () use ($scheme) {
            $scheme->tiers()->delete();
            $scheme->delete();
        });

        return response()->json(['success' => true, 'deactivated' => false]);
    }

    // ------------------------------------------------------------- internals

    /**
     * @return array|\Illuminate\Http\JsonResponse
     */
    private function validated(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:100',
            'description' => 'nullable|string|max:1000',
            'award_mode' => 'nullable|in:' . implode(',', WalletScheme::MODES),
            'is_active' => 'boolean',
            'starts_on' => 'nullable|date',
            'ends_on' => 'nullable|date|after_or_equal:starts_on',
            'tiers' => 'required|array|min:1',
            'tiers.*.appointments_from' => 'required|integer|min:1',
            'tiers.*.appointments_to' => 'nullable|integer|min:1',
            'tiers.*.coins_awarded' => 'required|integer|min:0',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();

        if ($error = $this->ladderProblem($data['tiers'])) {
            return response()->json(['message' => $error], 422);
        }

        return $data;
    }

    /**
     * Why this ladder does not hold together, or null when it does.
     *
     * @param  array<int, array>  $tiers
     */
    private function ladderProblem(array $tiers): ?string
    {
        usort($tiers, fn ($a, $b) => $a['appointments_from'] <=> $b['appointments_from']);

        if ($tiers[0]['appointments_from'] !== 1) {
            return 'The first rung has to start at appointment 1.';
        }

        $openEnded = 0;

        foreach ($tiers as $index => $tier) {
            $to = $tier['appointments_to'] ?? null;

            if ($to === null) {
                $openEnded++;

                if ($index !== count($tiers) - 1) {
                    return 'Only the last rung can be open-ended.';
                }

                continue;
            }

            if ($to < $tier['appointments_from']) {
                return "Rung {$tier['appointments_from']}–{$to} ends before it starts.";
            }

            $next = $tiers[$index + 1] ?? null;

            if ($next && $next['appointments_from'] !== $to + 1) {
                return "There is a gap or overlap between {$to} and {$next['appointments_from']}. "
                    . 'Rungs must run back to back.';
            }
        }

        if ($openEnded > 1) {
            return 'Only one rung can be open-ended.';
        }

        return null;
    }

    /**
     * @param  array<int, array>  $tiers
     */
    private function syncTiers(WalletScheme $scheme, array $tiers): void
    {
        usort($tiers, fn ($a, $b) => $a['appointments_from'] <=> $b['appointments_from']);

        $scheme->tiers()->delete();

        foreach ($tiers as $index => $tier) {
            $scheme->tiers()->create([
                'tier_order' => $index + 1,
                'appointments_from' => $tier['appointments_from'],
                'appointments_to' => $tier['appointments_to'] ?? null,
                // Legacy column, kept in step so older readers still work.
                'appointments_required' => $tier['appointments_from'],
                'coins_awarded' => $tier['coins_awarded'],
            ]);
        }
    }

    private function hasAwards(WalletScheme $scheme): bool
    {
        return WalletTransaction::whereIn('related_scheme_tier_id', $scheme->tiers->pluck('id'))
            ->exists();
    }

    private function present(WalletScheme $scheme): array
    {
        return [
            'id' => $scheme->id,
            'name' => $scheme->name,
            'description' => $scheme->description,
            'award_mode' => $scheme->award_mode,
            'is_active' => $scheme->is_active,
            'starts_on' => $scheme->starts_on?->toDateString(),
            'ends_on' => $scheme->ends_on?->toDateString(),
            'created_at' => $scheme->created_at,
            'tiers' => $scheme->tiers->map(fn ($tier) => [
                'id' => $tier->id,
                'tier_order' => $tier->tier_order,
                'appointments_from' => $tier->appointments_from,
                'appointments_to' => $tier->appointments_to,
                'coins_awarded' => $tier->coins_awarded,
                'label' => $tier->appointments_to === null
                    ? "From {$tier->appointments_from} onwards"
                    : "{$tier->appointments_from}–{$tier->appointments_to}",
            ])->values(),
        ];
    }
}
