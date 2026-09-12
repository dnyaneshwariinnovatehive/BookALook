<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class SalonController extends Controller
{
    public function index(Request $request)
    {
        $query = \App\Models\Salon::with(['admin', 'city', 'currentSubscription', 'assignedCollaborator:id,name,email']);

        if ($request->has('search') && $request->search != '') {
            $search = $request->input('search');
            $query->where(function($q) use ($search) {
                $q->where('name', 'like', "%{$search}%")
                  ->orWhereHas('city', function($qc) use ($search) {
                      $qc->where('name', 'like', "%{$search}%");
                  });
            });
        }

        if ($request->has('status') && $request->status != '') {
            $query->where('status', $request->input('status'));
        }

        $salons = $query->orderBy('created_at', 'desc')->paginate(20);

        return response()->json([
            'success' => true,
            'data' => $salons->items(),
            'meta' => [
                'current_page' => $salons->currentPage(),
                'last_page' => $salons->lastPage(),
                'total' => $salons->total(),
            ]
        ]);
    }

    public function show($id)
    {
        $salon = \App\Models\Salon::with([
            'admin',
            'city',
            'services.template.category',
            'providers.user',
            'combos.services',
            'currentSubscription',
            'assignedCollaborator:id,name,email',
        ])->findOrFail($id);

        return response()->json([
            'success' => true,
            'data' => $salon
        ]);
    }

    /**
     * Put a collaborator on a salon — or take one off.
     *
     * A salon that came in through an enquiry already carries the collaborator
     * the enquiry was assigned to. A salon that registered itself from the
     * partner app and was approved straight away never passed through that
     * step, so without this there was no way to give it a collaborator at all.
     * The directory is the one place that holds every salon regardless of how
     * it arrived, which is why the assignment lives here.
     */
    public function assignCollaborator(Request $request, $id)
    {
        $request->validate([
            // Null clears the assignment, so a wrong pick can be undone.
            'collaborator_id' => 'nullable|exists:users,id',
        ]);

        $salon = \App\Models\Salon::findOrFail($id);

        $collaborator = $request->filled('collaborator_id')
            ? \App\Models\User::where('role', 'collaborator')->findOrFail($request->collaborator_id)
            : null;

        $salon->update(['assigned_collaborator_id' => $collaborator?->id]);

        return response()->json([
            'success' => true,
            'message' => $collaborator
                ? "{$collaborator->name} is now the collaborator for {$salon->name}."
                : 'Collaborator removed from this salon.',
            'data' => $salon->fresh()->load('assignedCollaborator:id,name,email'),
        ]);
    }
}
