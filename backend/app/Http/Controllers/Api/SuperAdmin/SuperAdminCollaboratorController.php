<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\User;
use App\Models\Salon;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Validator;

class SuperAdminCollaboratorController extends Controller
{
    /**
     * Fetch all collaborators along with basic stats.
     */
    public function index()
    {
        $collaborators = User::where('role', 'collaborator')->get();

        $stats = $collaborators->map(function ($collaborator) {
            // Count salons where this collaborator is assigned
            $onboardedSalonsCount = Salon::where('assigned_collaborator_id', $collaborator->id)->count();

            return [
                'id' => $collaborator->id,
                'name' => $collaborator->name,
                'email' => $collaborator->email,
                'phone' => $collaborator->phone,
                'created_at' => $collaborator->created_at,
                'onboarded_salons_count' => $onboardedSalonsCount,
            ];
        });

        return response()->json([
            'success' => true,
            'data' => $stats
        ]);
    }

    /**
     * Create a new collaborator.
     */
    public function store(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:255',
            'email' => 'nullable|email|max:255|unique:users',
            'phone' => 'required|string|max:20|unique:users,phone',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $user = User::create([
            'name' => $request->name,
            'email' => $request->email,
            'phone' => $request->phone,
            'password_hash' => Hash::make(\Illuminate\Support\Str::random(12)),
            'role' => 'collaborator',
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Collaborator created successfully.',
            'data' => $user
        ], 201);
    }
}
