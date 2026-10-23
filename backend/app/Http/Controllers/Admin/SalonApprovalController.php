<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Services\AuditLogger;
use App\Services\WalletService;
use Illuminate\Http\Request;
use App\Models\Salon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class SalonApprovalController extends Controller
{
    /**
     * Display a listing of pending salons.
     */
    public function index(Request $request)
    {
        $request->validate([
            'page' => 'nullable|integer|min:1',
            'per_page' => 'nullable|integer|min:5|max:100',
            'search' => 'nullable|string|max:100',
            'city_id' => 'nullable|string|max:36',
            'sub_area_id' => 'nullable|string|max:36',
            'collaborator_id' => 'nullable|string|max:36',
            'column' => 'nullable|in:created_at,name,city,status',
            'direction' => 'nullable|in:asc,desc',
        ]);

        $status = $request->input('status');
        $query = Salon::with([
            'admin:id,name,email,phone',
            'city:id,name,state',
            'subArea:id,name',
            'assignedCollaborator:id,name',
            'preferredPlan',
        ]);

        if ($status) {
            $query->where('status', $status);
        } else {
            $query->whereIn('status', ['pending_approval', 'needs_correction']);
        }

        if ($request->filled('search')) {
            $search = $request->input('search');
            $query->where(function ($q) use ($search) {
                $q->where('name', 'like', "%{$search}%")
                  ->orWhereHas('admin', fn ($qa) => $qa->where('name', 'like', "%{$search}%"))
                  ->orWhereHas('city', fn ($qc) => $qc->where('name', 'like', "%{$search}%"))
                  ->orWhereHas('subArea', fn ($qs) => $qs->where('name', 'like', "%{$search}%"));
            });
        }

        if ($request->filled('city_id')) {
            $query->where('city_id', $request->input('city_id'));
        }

        if ($request->filled('sub_area_id')) {
            $query->where('sub_area_id', $request->input('sub_area_id'));
        }

        if ($request->filled('collaborator_id')) {
            $colId = $request->input('collaborator_id');
            if ($colId === 'unassigned') {
                $query->whereNull('assigned_collaborator_id');
            } else {
                $query->where('assigned_collaborator_id', $colId);
            }
        }

        $column = $request->input('column');
        $direction = $request->input('direction') === 'asc' ? 'asc' : 'desc';

        if ($column === 'city') {
            $query->orderBy(
                DB::table('cities')->select('name')->whereColumn('cities.id', 'salons.city_id')->limit(1),
                $direction
            );
        } elseif ($column && in_array($column, ['created_at', 'name', 'status'], true)) {
            $query->orderBy($column, $direction);
        } else {
            // Newest first, matching the enquiries queue above.
            $query->orderBy('created_at', 'desc');
        }
        $query->orderBy('id');

        $perPage = (int) $request->input('per_page', 20);
        $salons = $query->paginate($perPage);

        return response()->json([
            'success' => true,
            // `data` stays a plain list of salons; the meta block is additive.
            'data' => $salons->items(),
            'meta' => [
                'current_page' => $salons->currentPage(),
                'last_page' => $salons->lastPage(),
                'per_page' => $salons->perPage(),
                'total' => $salons->total(),
            ],
        ]);
    }

    /**
     * Display the specified salon details.
     */
    public function show($id)
    {
        $salon = Salon::with([
            'admin',
            'city',
            'subArea',
            'media',
            'workingHours',
            'services.template.category',
            'assignedCollaborator',
            'preferredPlan',
        ])->findOrFail($id);

        return response()->json([
            'success' => true,
            'data' => $salon
        ]);
    }

    /**
     * Approve the salon.
     */
    public function approve(Request $request, $id, WalletService $wallet)
    {
        $salon = Salon::findOrFail($id);
        $previousStatus = $salon->status;

        $targetModel = $request->input('commercial_model', $salon->preferred_commercial_model ?? 'subscription');
        $isCommission = ($targetModel === 'commission');

        if ($isCommission) {
            $request->validate([
                'commission_percentage' => 'required|numeric|min:0|max:100',
            ]);
        }

        // Generate a dummy QR code URL for now (e.g. using qrserver API)
        $dummyQrCodeUrl = 'https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=salon_' . $salon->id;

        $updateData = [
            'status' => 'active',
            'qr_code_url' => $dummyQrCodeUrl,
            'approved_at' => now(),
            'approved_by' => $request->user()?->id,
            'rejection_reason' => null,
            'correction_notes' => null,
        ];

        if ($isCommission) {
            $updateData['commission_opt_in'] = true;
            $updateData['commission_percentage'] = $request->input('commission_percentage');
            $updateData['commission_rate_effective_from'] = now()->toDateString();
        } else {
            $updateData['commission_opt_in'] = false;
        }

        $salon->update($updateData);

        // The owner's next screen asks them to buy a plan, so the coins that
        // help pay for it have to be in the wallet before they get there.
        // Idempotent, so re-approving never hands out a second bonus.
        $bonus = $wallet->grantWelcomeBonus($salon->refresh());

        AuditLogger::record(
            action: AuditLog::SALON_APPROVED,
            entity: $salon,
            label: $salon->name,
            before: ['status' => $previousStatus],
            after: ['status' => 'active'],
            metadata: array_filter([
                'welcome_coins_granted' => $bonus['granted'] > 0 ? $bonus['granted'] : null,
                'commission_percentage' => $isCommission ? $request->input('commission_percentage') : null,
                'commercial_model' => $targetModel,
            ]),
        );

        $message = 'Salon approved successfully. QR Code generated.';

        if ($bonus['granted'] > 0) {
            $message .= " {$bonus['granted']} welcome coins added to their wallet.";
        }

        return response()->json([
            'success' => true,
            'message' => $message,
            'welcome_bonus_coins' => $bonus['granted'],
            'wallet_balance' => $bonus['balance'],
            'data' => $salon->fresh()->load([
                'admin', 'city', 'subArea', 'media', 'workingHours', 'services.template.category', 'assignedCollaborator', 'preferredPlan',
            ]),
        ]);
    }

    /**
     * Request corrections on a salon registration.
     */
    public function requestCorrections(Request $request, $id)
    {
        $request->validate([
            'correction_notes' => 'required|string|max:1000',
        ]);

        $salon = Salon::findOrFail($id);
        $previousStatus = $salon->status;

        $salon->update([
            'status' => 'needs_correction',
            'correction_notes' => $request->correction_notes,
            'rejection_reason' => $request->correction_notes,
            'correction_requested_at' => now(),
        ]);

        AuditLogger::record(
            action: 'salon.correction_requested',
            entity: $salon,
            label: $salon->name,
            before: ['status' => $previousStatus],
            after: ['status' => 'needs_correction'],
            metadata: ['notes' => $request->correction_notes],
        );

        if ($salon->enquiry_id) {
            $salon->enquiry()->update(['status' => 'assigned']);
        }

        return response()->json([
            'success' => true,
            'message' => 'Salon returned for corrections.',
            'data' => $salon,
        ]);
    }

    /**
     * Reject the salon.
     */
    public function reject(Request $request, $id)
    {
        $request->validate([
            'rejection_reason' => 'required|string|max:500'
        ]);

        $salon = Salon::findOrFail($id);
        $previousStatus = $salon->status;

        $salon->update([
            'status' => 'rejected',
            'rejection_reason' => $request->rejection_reason,
            'correction_notes' => null,
        ]);

        AuditLogger::record(
            action: AuditLog::SALON_REJECTED,
            entity: $salon,
            label: $salon->name,
            before: ['status' => $previousStatus],
            after: ['status' => 'rejected'],
            metadata: ['reason' => $request->rejection_reason],
        );

        // A salon a collaborator onboarded is not finished when it is rejected
        // — it goes back on their list so they can fix what was wrong and send
        // it again. Without this the enquiry would sit at 'onboarded' forever
        // and the collaborator would have no way back to it.
        if ($salon->enquiry_id) {
            $salon->enquiry()->update(['status' => 'assigned']);
        }

        return response()->json([
            'success' => true,
            'message' => 'Salon rejected successfully.',
            'data' => $salon
        ]);
    }
}
