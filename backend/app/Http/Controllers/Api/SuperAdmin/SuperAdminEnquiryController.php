<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\SalonEnquiry;
use App\Models\User;
use App\Services\AuditLogger;
use Illuminate\Http\Request;

class SuperAdminEnquiryController extends Controller
{
    /**
     * Enquiries waiting to be handed to somebody, each carrying the place it
     * came from so the page can put the right collaborator in front of it.
     */
    public function index(Request $request)
    {
        $request->validate([
            'page' => 'nullable|integer|min:1',
            'per_page' => 'nullable|integer|min:5|max:100',
            'search' => 'nullable|string|max:100',
            'column' => 'nullable|in:created_at,salon_name,owner_name,city,status',
            'direction' => 'nullable|in:asc,desc',
        ]);

        $query = SalonEnquiry::with([
            'assignedCollaborator:id,name,city_id,sub_area_id',
            'cityRecord:id,name,state',
            'subArea:id,name',
        ]);

        if ($request->filled('search')) {
            $search = $request->input('search');
            $query->where(function ($q) use ($search) {
                $q->where('salon_name', 'like', "%{$search}%")
                  ->orWhere('owner_name', 'like', "%{$search}%")
                  ->orWhere('city', 'like', "%{$search}%")
                  ->orWhere('phone', 'like', "%{$search}%");
            });
        }

        $column = $request->input('column');
        $direction = $request->input('direction') === 'asc' ? 'asc' : 'desc';

        if ($column && in_array($column, ['created_at', 'salon_name', 'owner_name', 'city', 'status'], true)) {
            $query->orderBy($column, $direction);
        } else {
            $query->orderByDesc('created_at');
        }
        $query->orderBy('id');

        $perPage = (int) $request->input('per_page', 20);
        $paged = $query->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => $paged->getCollection()->map(fn (SalonEnquiry $enquiry) => $enquiry->toArray() + [
                // A resolved city wins; the typed string is the fallback for
                // the older rows that predate city_id.
                'city_name' => $enquiry->cityRecord->name ?? $enquiry->city,
                'city_state' => $enquiry->cityRecord->state ?? null,
                'sub_area_name' => $enquiry->subArea->name ?? null,
                'location_label' => $this->locationLabel(
                    $enquiry->subArea->name ?? null,
                    $enquiry->cityRecord->name ?? $enquiry->city
                ),
            ])->values(),
            'meta' => [
                'current_page' => $paged->currentPage(),
                'last_page' => $paged->lastPage(),
                'per_page' => $paged->perPage(),
                'total' => $paged->total(),
            ],
        ]);
    }

    /**
     * Collaborators, with where each one works.
     *
     * The page uses this to sort by proximity to an enquiry, so the locality
     * has to come with them — a list of bare names cannot be ranked against
     * anything.
     */
    public function getCollaborators()
    {
        $collaborators = User::with(['city:id,name,state', 'subArea:id,name'])
            ->where('role', 'collaborator')
            ->orderBy('name')
            ->get(['id', 'name', 'email', 'phone', 'city_id', 'sub_area_id']);

        return response()->json([
            'success' => true,
            'data' => $collaborators->map(fn (User $user) => [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
                'phone' => $user->phone,
                'city_id' => $user->city_id,
                'sub_area_id' => $user->sub_area_id,
                'city_name' => $user->city->name ?? null,
                'sub_area_name' => $user->subArea->name ?? null,
                'location_label' => $this->locationLabel(
                    $user->subArea->name ?? null,
                    $user->city->name ?? null
                ),
                // Nothing to match on. The page says so rather than ranking
                // them last for no visible reason.
                'has_location' => $user->city_id !== null,
            ]),
        ]);
    }

    /** "Kothrud, Pune" — or whichever half of it exists. */
    private function locationLabel(?string $subArea, ?string $city): ?string
    {
        return collect([$subArea, $city])->filter()->implode(', ') ?: null;
    }

    /**
     * Assign a collaborator to an enquiry.
     */
    public function assignCollaborator(Request $request, $id)
    {
        $request->validate([
            'collaborator_id' => 'required|exists:users,id'
        ]);

        $enquiry = SalonEnquiry::with(['cityRecord', 'subArea'])->findOrFail($id);
        $previous = $enquiry->assignedCollaborator?->name;

        $collaborator = User::where('role', 'collaborator')->findOrFail($request->collaborator_id);

        $enquiry->update([
            'assigned_collaborator_id' => $collaborator->id,
            'assigned_at' => now(),
            'status' => 'assigned'
        ]);

        AuditLogger::record(
            action: AuditLog::SALON_COLLABORATOR_ASSIGNED,
            label: $enquiry->salon_name,
            before: ['collaborator' => $previous],
            after: ['collaborator' => $collaborator->name],
            metadata: [
                'enquiry_id' => $enquiry->id,
                'enquiry_location' => $this->locationLabel(
                    $enquiry->subArea->name ?? null,
                    $enquiry->cityRecord->name ?? $enquiry->city
                ),
            ],
        );

        return response()->json([
            'success' => true,
            'message' => 'Collaborator assigned successfully.',
            'data' => $enquiry->load('assignedCollaborator')
        ]);
    }
}
