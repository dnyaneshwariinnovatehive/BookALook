<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\SalonEnquiry;

class CollaboratorController extends Controller
{
    /**
     * Get enquiries assigned to the authenticated collaborator.
     */
    public function getAssignedEnquiries(Request $request)
    {
        $user = $request->user();

        // Ensure only collaborators can access this (though middleware usually handles it, double check)
        if ($user->role !== 'collaborator') {
            return response()->json([
                'success' => false,
                'message' => 'Unauthorized access. Only collaborators can view this data.'
            ], 403);
        }

        $enquiries = SalonEnquiry::where('assigned_collaborator_id', $user->id)
            ->where('status', 'assigned')
            ->orderBy('assigned_at', 'desc')
            ->get();

        return response()->json([
            'success' => true,
            'data' => $enquiries
        ]);
    }
}
