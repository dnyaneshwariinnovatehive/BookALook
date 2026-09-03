<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\SalonEnquiry;
use App\Models\User;

class SuperAdminEnquiryController extends Controller
{
    /**
     * Fetch all public enquiries.
     */
    public function index()
    {
        $enquiries = SalonEnquiry::with('assignedCollaborator')
            ->orderBy('created_at', 'desc')
            ->get();

        return response()->json([
            'success' => true,
            'data' => $enquiries
        ]);
    }

    /**
     * Fetch users eligible to be collaborators.
     */
    public function getCollaborators()
    {
        $collaborators = User::where('role', 'collaborator')->get(['id', 'name', 'email']);

        return response()->json([
            'success' => true,
            'data' => $collaborators
        ]);
    }

    /**
     * Assign a collaborator to an enquiry.
     */
    public function assignCollaborator(Request $request, $id)
    {
        $request->validate([
            'collaborator_id' => 'required|exists:users,id'
        ]);

        $enquiry = SalonEnquiry::findOrFail($id);
        
        $collaborator = User::where('role', 'collaborator')->findOrFail($request->collaborator_id);

        $enquiry->update([
            'assigned_collaborator_id' => $collaborator->id,
            'assigned_at' => now(),
            'status' => 'assigned'
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Collaborator assigned successfully.',
            'data' => $enquiry->load('assignedCollaborator')
        ]);
    }
}
