<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use App\Models\PlatformPolicySetting;
use App\Models\Salon;
use App\Models\SalonEnquiry;
use App\Models\SalonSubscription;
use App\Models\ServiceCategory;
use App\Services\SalonAccessService;
use App\Services\SalonOnboardingService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

/**
 * What a collaborator does in the partner app.
 *
 * A collaborator has no salon of their own, so none of this sits behind the
 * salon.active gate. They work one assignment at a time: SuperAdmin hands them
 * an enquiry, they go and build the salon's profile on site, and they submit it
 * for approval. They cannot invent a salon that nobody enquired about — the
 * assignment is the only way in.
 */
class CollaboratorController extends Controller
{
    public function __construct(
        private SalonOnboardingService $onboarding,
        private SalonAccessService $access,
    ) {
    }

    /**
     * Enquiries assigned to the authenticated collaborator and still waiting to
     * be onboarded.
     */
    public function getAssignedEnquiries(Request $request)
    {
        $user = $this->collaborator($request);

        if (! $user) {
            return $this->notACollaborator();
        }

        $enquiries = SalonEnquiry::with('salon:id,name,status,rejection_reason,enquiry_id')
            ->where('assigned_collaborator_id', $user->id)
            ->where('status', 'assigned')
            ->orderBy('assigned_at', 'desc')
            ->get()
            ->map(function (SalonEnquiry $enquiry) {
                // A rejected salon puts its enquiry back on this list. The app
                // needs to tell that apart from a fresh assignment, or the
                // collaborator would retype a profile that already exists.
                $rejected = $enquiry->salon && $enquiry->salon->status === 'rejected';

                return $enquiry->only([
                    'id', 'salon_name', 'owner_name', 'phone', 'city', 'message', 'assigned_at',
                ]) + [
                    'needs_correction' => $rejected,
                    'rejection_reason' => $rejected ? $enquiry->salon->rejection_reason : null,
                    'salon_id' => $enquiry->salon?->id,
                ];
            });

        return response()->json([
            'success' => true,
            'data' => $enquiries,
        ]);
    }

    /**
     * Salons SuperAdmin handed this collaborator straight from the directory.
     *
     * A salon that registered itself from the partner app never produced an
     * enquiry, so it cannot arrive as an onboarding task — it already exists and
     * has an owner. SuperAdmin assigns one anyway to give it a human: somebody
     * to chase a lapsed plan, finish a half-built menu, or answer the owner's
     * questions. Without this endpoint that assignment was invisible to the very
     * person it named.
     *
     * Deliberately separate from the enquiry list, because the two need
     * different things doing: one is "go build this", the other is "look after
     * this".
     */
    public function assignedSalons(Request $request)
    {
        $user = $this->collaborator($request);

        if (! $user) {
            return $this->notACollaborator();
        }

        $this->access->expireStale();

        $salons = Salon::with(['city:id,name', 'admin:id,name,phone', 'currentSubscription.plan:id,name'])
            ->withCount(['services' => fn ($q) => $q->where('is_active', true)])
            ->where('assigned_collaborator_id', $user->id)
            // Salons this collaborator onboarded themselves live under My
            // Salons; this list is only the ones handed over ready-made.
            ->whereNull('enquiry_id')
            ->whereIn('status', ['active', 'pending_approval', 'suspended'])
            ->orderByDesc('updated_at')
            ->get()
            ->map(function (Salon $salon) {
                $subscription = $salon->currentSubscription;
                $daysLeft = $subscription
                    ? (int) Carbon::today()->diffInDays(Carbon::parse($subscription->end_date), false)
                    : null;

                return [
                    'id' => $salon->id,
                    'name' => $salon->name,
                    'status' => $salon->status,
                    'cover_photo_url' => $salon->cover_photo_url,
                    'address' => $salon->address,
                    'city' => $salon->city?->name,
                    'owner_name' => $salon->admin?->name,
                    'owner_phone' => $salon->admin?->phone,
                    'services_count' => $salon->services_count,
                    'plan_name' => $subscription?->plan?->name,
                    'days_left' => $daysLeft,
                    // No plan at all means the owner has never chosen one, which
                    // is the single most useful thing a collaborator can help
                    // with on a self-registered salon.
                    'needs_plan' => $subscription === null,
                    'registered_at' => $salon->created_at,
                ];
            });

        return response()->json([
            'success' => true,
            'data' => $salons,
        ]);
    }

    /**
     * Everything this collaborator has submitted, with where it got to.
     *
     * A rejected salon is not a dead end — it comes back here with SuperAdmin's
     * reason and can be corrected and sent again, so the enquiry travels with
     * it.
     */
    public function onboardedSalons(Request $request)
    {
        $user = $this->collaborator($request);

        if (! $user) {
            return $this->notACollaborator();
        }

        $salons = Salon::with(['city:id,name,state', 'admin:id,name,phone', 'enquiry'])
            ->withCount('services')
            ->where('assigned_collaborator_id', $user->id)
            ->whereNotNull('enquiry_id')
            ->orderByDesc('created_at')
            ->get()
            ->map(fn (Salon $salon) => [
                'id' => $salon->id,
                'name' => $salon->name,
                'status' => $salon->status,
                'rejection_reason' => $salon->rejection_reason,
                'cover_photo_url' => $salon->cover_photo_url,
                'address' => $salon->address,
                'city' => $salon->city?->name,
                'services_count' => $salon->services_count,
                'owner_name' => $salon->admin?->name,
                'owner_phone' => $salon->admin?->phone,
                'submitted_at' => $salon->created_at,
                'enquiry_id' => $salon->enquiry_id,
                'services_priced' => $salon->services_count > 0,
                // Editable right up to approval, and never again after it. Once
                // a salon is live it belongs to its owner.
                'can_edit' => in_array($salon->status, ['pending_approval', 'rejected'], true),
            ]);

        return response()->json([
            'success' => true,
            'data' => $salons,
        ]);
    }

    /**
     * The collaborator's own record, plus the tally of what they have done.
     *
     * The numbers belong here rather than on a separate stats call because the
     * profile screen is the one place a collaborator sees their whole
     * contribution at once, and it should not need three round trips to draw.
     */
    public function profile(Request $request)
    {
        $user = $this->collaborator($request);

        if (! $user) {
            return $this->notACollaborator();
        }

        $byStatus = Salon::where('assigned_collaborator_id', $user->id)
            ->whereNotNull('enquiry_id')
            ->selectRaw('status, count(*) as total')
            ->groupBy('status')
            ->pluck('total', 'status');

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $user->id,
                'name' => $user->name,
                // The login identity. Shown, never editable from here — changing
                // it would lock them out of their own OTP.
                'phone' => $user->phone,
                'email' => $user->email,
                'gender' => $user->gender,
                'date_of_birth' => $user->date_of_birth?->toDateString(),
                'address' => $user->address,
                'pincode' => $user->pincode,
                'joined_at' => $user->created_at,
                'stats' => [
                    'assigned' => SalonEnquiry::where('assigned_collaborator_id', $user->id)
                        ->where('status', 'assigned')->count(),
                    'submitted' => (int) $byStatus->sum(),
                    'approved' => (int) ($byStatus['active'] ?? 0),
                    'pending' => (int) ($byStatus['pending_approval'] ?? 0),
                    'rejected' => (int) ($byStatus['rejected'] ?? 0),
                ],
            ],
        ]);
    }

    /**
     * Update the collaborator's own contact details.
     *
     * Phone is deliberately absent: it is how they sign in, so changing it here
     * would be a way to lock yourself out of the app from inside the app.
     */
    public function updateProfile(Request $request)
    {
        $user = $this->collaborator($request);

        if (! $user) {
            return $this->notACollaborator();
        }

        $data = $request->validate([
            'name' => 'required|string|max:150',
            'email' => 'nullable|email|max:150|unique:users,email,' . $user->id,
            'gender' => 'nullable|in:male,female,other,unspecified',
            'date_of_birth' => 'nullable|date|before:today',
            'address' => 'nullable|string|max:500',
            'pincode' => 'nullable|string|max:10',
        ]);

        $user->update($data);

        return response()->json([
            'success' => true,
            'message' => 'Profile updated.',
        ]);
    }

    /**
     * Salons this collaborator onboarded whose plan is running out.
     *
     * A collaborator cannot renew anything — they are not the customer. What
     * they can do is ring the owner they already met, which is exactly the sort
     * of save that keeps a salon they set up from quietly going dark. So the
     * alert carries the owner's number and nothing resembling a pay button.
     *
     * Computed on read rather than trusted from the reminder job, so it is
     * never a day stale and never depends on the cron having run.
     */
    public function alerts(Request $request)
    {
        $user = $this->collaborator($request);

        if (! $user) {
            return $this->notACollaborator();
        }

        $warningDays = (int) PlatformPolicySetting::value('subscription_expiry_warning_days');
        $this->access->expireStale();

        // Every salon in this collaborator's care, however it got there — one
        // they onboarded, or one SuperAdmin handed them from the directory.
        $salons = Salon::with(['admin:id,name,phone', 'city:id,name'])
            ->where('assigned_collaborator_id', $user->id)
            ->where('status', 'active')
            ->get();

        $alerts = [];

        foreach ($salons as $salon) {
            $subscription = SalonSubscription::where('salon_id', $salon->id)
                ->where('status', 'active')
                ->latest('start_date')
                ->first();

            // Never subscribed at all is onboarding, not a lapse — that salon
            // is waiting on its owner to choose a first plan, which the welcome
            // screen already handles.
            $everSubscribed = $subscription
                || SalonSubscription::where('salon_id', $salon->id)->exists();

            if (! $everSubscribed) {
                continue;
            }

            if (! $subscription) {
                $alerts[] = $this->alert($salon, 'lapsed', null);
                continue;
            }

            $daysLeft = (int) Carbon::today()->diffInDays(Carbon::parse($subscription->end_date), false);

            if ($daysLeft <= $warningDays) {
                $alerts[] = $this->alert($salon, 'expiring', $daysLeft);
            }
        }

        // Worst first: a salon already offline needs the call before one that
        // has three days left.
        usort($alerts, fn ($a, $b) => ($a['days_left'] ?? -999) <=> ($b['days_left'] ?? -999));

        return response()->json([
            'success' => true,
            'warning_days' => $warningDays,
            'data' => $alerts,
        ]);
    }

    /** @return array<string, mixed> */
    private function alert(Salon $salon, string $severity, ?int $daysLeft): array
    {
        return [
            'salon_id' => $salon->id,
            'salon_name' => $salon->name,
            'city' => $salon->city?->name,
            'owner_name' => $salon->admin?->name,
            'owner_phone' => $salon->admin?->phone,
            'severity' => $severity,
            'days_left' => $daysLeft,
            'message' => match (true) {
                $severity === 'lapsed' => "{$salon->name} is offline — its plan has run out and customers cannot find it.",
                $daysLeft <= 0 => "{$salon->name}'s plan ends today.",
                $daysLeft === 1 => "{$salon->name}'s plan ends tomorrow.",
                default => "{$salon->name}'s plan ends in {$daysLeft} days.",
            },
        ];
    }

    /**
     * A salon SuperAdmin sent back, in the shape the onboarding form fills
     * itself from.
     *
     * Without this a rejection would mean retyping the entire visit to change
     * one line, which is the sort of thing that makes a collaborator stop
     * bothering. Photos are returned as URLs rather than files — the device
     * cannot edit what it no longer holds, so re-uploading is how they change.
     */
    public function submittedSalon(Request $request, string $salonId)
    {
        $user = $this->collaborator($request);

        if (! $user) {
            return $this->notACollaborator();
        }

        $salon = Salon::with(['admin:id,name,phone,email', 'workingHours', 'media', 'services.template.category'])
            ->where('assigned_collaborator_id', $user->id)
            ->find($salonId);

        if (! $salon) {
            return response()->json([
                'success' => false,
                'message' => 'You did not onboard this salon.',
            ], 403);
        }

        return response()->json([
            'success' => true,
            'data' => [
                'salon_name' => $salon->name,
                'description' => $salon->description,
                'address' => $salon->address,
                'city_id' => $salon->city_id,
                'pincode' => $salon->pincode,
                'salon_phone' => $salon->phone_num,
                'gender_focus' => $salon->gender_focus,
                'latitude' => $salon->latitude === null ? null : (float) $salon->latitude,
                'longitude' => $salon->longitude === null ? null : (float) $salon->longitude,
                'owner_name' => $salon->admin?->name,
                'owner_phone' => $salon->admin?->phone,
                'owner_email' => $salon->admin?->email,
                'working_hours' => $salon->workingHours->map(fn ($hour) => [
                    'day_of_week' => (int) $hour->day_of_week,
                    'is_closed' => (bool) $hour->is_closed,
                    'open_time' => $hour->open_time ? substr($hour->open_time, 0, 5) : null,
                    'close_time' => $hour->close_time ? substr($hour->close_time, 0, 5) : null,
                ])->values(),
                'services' => $salon->services->map(fn ($service) => [
                    'template_id' => $service->template_id,
                    'name' => $service->template->name ?? 'Service',
                    'category_name' => $service->template->category->name ?? '',
                    'duration_minutes' => (int) ($service->template->estimated_duration_minutes ?? 30),
                    'price' => (float) $service->price,
                    'description' => $service->description,
                ])->values(),
                'photo_urls' => $salon->media->pluck('file_url')->values(),
            ],
        ]);
    }

    /**
     * The service catalog, so a collaborator can price a salon's menu on site.
     *
     * The admin app reaches this through a salon it belongs to. A collaborator
     * has no salon until the one they are building exists, so they get the
     * standard catalog only — custom templates belong to a salon and there is
     * not one yet.
     */
    public function masterCatalog(Request $request)
    {
        if (! $this->collaborator($request)) {
            return $this->notACollaborator();
        }

        $categories = ServiceCategory::with(['templates' => function ($query) {
            $query->where('is_active', true)->where('is_custom', false);
        }])
            ->where('is_active', true)
            ->where('is_custom', false)
            ->orderBy('display_order')
            ->get();

        return response()->json([
            'success' => true,
            'categories' => $categories,
        ]);
    }

    /**
     * Submit a built salon for SuperAdmin approval.
     *
     * Arrives as one multipart request because the collaborator may have been
     * offline when they filled it in: the device holds the whole draft and
     * replays it in a single shot when signal returns. Replaying a submission
     * that already landed is therefore normal, and answers with the salon that
     * exists rather than building a second one.
     */
    public function onboard(Request $request, string $enquiryId)
    {
        $user = $this->collaborator($request);

        if (! $user) {
            return $this->notACollaborator();
        }

        $enquiry = SalonEnquiry::find($enquiryId);

        if (! $enquiry || $enquiry->assigned_collaborator_id !== $user->id) {
            return response()->json([
                'success' => false,
                'message' => 'This enquiry is not assigned to you.',
            ], 403);
        }

        $data = $this->validateSubmission($request);

        try {
            $result = $this->onboarding->onboard(
                $enquiry,
                $user,
                $data,
                $request->file('photos') ?? []
            );
        } catch (\RuntimeException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], 422);
        }

        return response()->json([
            'success' => true,
            'message' => match (true) {
                $result['created'] => 'Salon submitted for SuperAdmin approval.',
                $result['resubmitted'] => 'Changes saved. The salon is with SuperAdmin for approval.',
                default => 'This salon is already approved and can no longer be edited.',
            },
            'already_submitted' => ! $result['created'] && ! $result['resubmitted'],
            'data' => $result['salon'],
        ], $result['created'] ? 201 : 200);
    }

    /**
     * The profile is compulsory; the menu is not. Hours and services arrive as
     * JSON strings because the request is multipart — it is carrying photos.
     *
     * @return array<string, mixed>
     */
    private function validateSubmission(Request $request): array
    {
        $request->merge([
            'working_hours' => $this->decodeList($request->input('working_hours')),
            'services' => $this->decodeList($request->input('services')),
        ]);

        $data = $request->validate([
            // Owner. Prefilled from the enquiry, but a collaborator standing in
            // front of them can correct it — and has to confirm it either way.
            'owner_name' => 'required|string|max:150',
            'owner_phone' => 'required|string|min:10|max:15',
            // The one owner field that stays optional: plenty of salon owners
            // have no email, and nothing in the platform needs one.
            'owner_email' => 'nullable|email|max:150',

            'salon_name' => 'required|string|max:150',
            // Customers are shown this instead of a phone number, so a salon
            // with no description has nothing selling it.
            'description' => 'required|string',
            'address' => 'required|string',
            'city_id' => 'required|exists:cities,id',
            'pincode' => 'required|string|max:10',
            'salon_phone' => 'required|string|max:20',
            'gender_focus' => 'required|in:Unisex,Men Only,Women Only',
            // Optional: GPS can simply fail indoors, and a missing pin falls
            // back to the city centre rather than blocking the visit.
            'latitude' => 'nullable|numeric|between:-90,90',
            'longitude' => 'nullable|numeric|between:-180,180',

            'working_hours' => 'required|array|min:1',
            'working_hours.*.day_of_week' => 'required|integer|between:0,6',
            'working_hours.*.is_closed' => 'boolean',
            'working_hours.*.open_time' => 'nullable|date_format:H:i',
            'working_hours.*.close_time' => 'nullable|date_format:H:i',

            // Optional by design — an owner can price their own menu later.
            'services' => 'array',
            'services.*.template_id' => 'nullable|uuid|exists:service_templates,id',
            'services.*.price' => 'required|numeric|min:0',
            'services.*.description' => 'nullable|string',
            'services.*.advance_percentage' => 'nullable|numeric|min:0|max:100',
            'services.*.gender_focus' => 'nullable|in:Unisex,Men Only,Women Only',
            'services.*.category_id' => 'nullable|string',
            'services.*.custom_category_name' => 'nullable|string|max:80',
            'services.*.custom_template_name' => 'required_without:services.*.template_id|nullable|string|max:150',
            'services.*.estimated_duration_minutes' => 'required_without:services.*.template_id|nullable|integer|min:15',

            'photos' => 'array|max:10',
            'photos.*' => 'image|mimes:jpeg,png,jpg,webp|max:5120',
            'cover_index' => 'nullable|integer|min:0',
        ]);

        $this->assertOpeningHoursMakeSense($data['working_hours'] ?? []);
        $this->assertSalonEverOpens($data['working_hours'] ?? []);

        return $data;
    }

    /**
     * A salon closed all seven days cannot take a booking, so submitting one is
     * always a mistake rather than a choice.
     */
    private function assertSalonEverOpens(array $days): void
    {
        $open = collect($days)->reject(
            fn ($day) => filter_var($day['is_closed'] ?? false, FILTER_VALIDATE_BOOLEAN)
        );

        if ($open->isEmpty()) {
            throw ValidationException::withMessages([
                'working_hours' => 'The salon has to be open at least one day a week.',
            ]);
        }
    }

    /**
     * A day that is open needs both ends of its window, and the close has to
     * come after the open. Caught here rather than at booking time, when the
     * collaborator is long gone.
     */
    private function assertOpeningHoursMakeSense(array $days): void
    {
        foreach ($days as $index => $day) {
            if (filter_var($day['is_closed'] ?? false, FILTER_VALIDATE_BOOLEAN)) {
                continue;
            }

            $open = $day['open_time'] ?? null;
            $close = $day['close_time'] ?? null;

            if (! $open || ! $close) {
                throw ValidationException::withMessages([
                    "working_hours.{$index}" => 'An open day needs both an opening and a closing time.',
                ]);
            }

            if ($close <= $open) {
                throw ValidationException::withMessages([
                    "working_hours.{$index}" => 'Closing time must be after opening time.',
                ]);
            }
        }
    }

    /** @return array<int, mixed> */
    private function decodeList(mixed $value): array
    {
        if (is_array($value)) {
            return $value;
        }

        if (! is_string($value) || $value === '') {
            return [];
        }

        $decoded = json_decode($value, true);

        return is_array($decoded) ? $decoded : [];
    }

    private function collaborator(Request $request): ?\App\Models\User
    {
        $user = $request->user();

        return $user && $user->role === 'collaborator' ? $user : null;
    }

    private function notACollaborator()
    {
        return response()->json([
            'success' => false,
            'message' => 'Unauthorized access. Only collaborators can view this data.',
        ], 403);
    }
}
