<?php

namespace App\Services;

use App\Models\Salon;
use App\Models\SalonEnquiry;
use App\Models\SalonMedia;
use App\Models\SalonWorkingHour;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceTemplate;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * Turning an assigned enquiry into a salon awaiting approval.
 *
 * A collaborator does this standing in someone else's salon, often on a bad
 * connection, so the whole submission arrives as one payload and is written in
 * one transaction. There is no half-built salon to come back to: either the
 * profile, its hours, its services and its photos all landed, or none of them
 * did and the device still holds the draft.
 *
 * Re-submitting the same enquiry is safe on purpose. A collaborator whose
 * upload succeeded but whose response was lost will retry, and that retry must
 * not produce a second salon.
 */
class SalonOnboardingService
{
    /** Where photos land on the public disk. */
    private const PHOTO_DIR = 'salon_media';

    /**
     * A collaborator's work on a salon ends the moment SuperAdmin approves it.
     *
     * Up to that point the salon is still theirs to correct — a typo spotted on
     * the drive home is worth fixing. After approval it belongs to its owner,
     * and a collaborator editing a live salon's prices from the field is not
     * something the platform should allow.
     */
    private const EDITABLE_STATUSES = ['pending_approval', 'rejected', 'needs_correction'];

    /**
     * @param  array<string, mixed>  $payload
     * @param  UploadedFile[]  $photos
     * @return array{salon: Salon, created: bool, resubmitted: bool}
     */
    public function onboard(SalonEnquiry $enquiry, User $collaborator, array $payload, array $photos = []): array
    {
        return DB::transaction(function () use ($enquiry, $collaborator, $payload, $photos) {
            // The same draft can legitimately be in flight twice at the same
            // moment: the Submit button on the last step and the device's own
            // background retry queue both send it, and neither one can see the
            // other. Locking the enquiry row makes the second attempt queue
            // behind the first, so it runs against the rows the first one wrote
            // instead of interleaving with them.
            //
            // Without this the two transactions interleave their writes to
            // salon_working_hours and the second one trips the
            // (salon_id, day_of_week) unique constraint on the very first day
            // it inserts.
            $enquiry = $enquiry->newQuery()->lockForUpdate()->findOrFail($enquiry->id);

            // Re-read inside the lock. Reading it before the transaction is what
            // let both attempts believe they were the first to see the salon.
            $existing = $enquiry->salon()->first();

            // Approved, suspended or deactivated: the collaborator is done here.
            // Also the landing spot for a retried submission of a salon that has
            // since gone live, which must not be rewritten by a stale draft.
            if ($existing && ! in_array($existing->status, self::EDITABLE_STATUSES, true)) {
                return ['salon' => $existing->load('city:id,name,state'), 'created' => false, 'resubmitted' => false];
            }

            // Inside the transaction too, for the same reason: creating the owner
            // races on the unique users.phone column just as badly.
            $owner = $this->resolveOwner($enquiry, $payload);

            if (! $existing) {
                $existing = Salon::where('enquiry_id', $enquiry->id)
                    ->whereIn('status', self::EDITABLE_STATUSES)
                    ->lockForUpdate()
                    ->first();
            }

            if (! $existing) {
                $existing = Salon::where('submitted_by', $collaborator->id)
                    ->where('admin_id', $owner->id)
                    ->whereRaw('LOWER(TRIM(name)) = ?', [mb_strtolower(trim($payload['salon_name']))])
                    ->whereIn('status', self::EDITABLE_STATUSES)
                    ->lockForUpdate()
                    ->first();
            }

            $salon = $existing
                ? $this->reviseSalon($existing, $owner, $payload)
                : $this->createSalon($enquiry, $collaborator, $owner, $payload);

            $this->writeWorkingHours($salon, $payload['working_hours'] ?? []);
            if (array_key_exists('services', $payload)) {
                $this->writeServices($salon, $payload['services'] ?? [], true);
            }
            $this->storePhotos($salon, $collaborator, $photos, (int) ($payload['cover_index'] ?? 0));

            // The enquiry's job is done the moment the salon exists. Whether it
            // is approved is the salon's status to carry, not the enquiry's.
            $enquiry->update(['status' => 'onboarded']);

            return [
                'salon' => $salon->fresh()->load('city:id,name,state'),
                'created' => ! $existing,
                'resubmitted' => (bool) $existing,
            ];
        });
    }

    /**
     * Submit a salon onboarded directly by a collaborator without an enquiry.
     *
     * @param  array<string, mixed>  $payload
     * @param  UploadedFile[]  $photos
     * @return array{salon: Salon, created: bool, resubmitted: bool}
     */
    public function onboardDirect(User $collaborator, array $payload, array $photos = [], ?Salon $existingSalon = null): array
    {
        return DB::transaction(function () use ($collaborator, $payload, $photos, $existingSalon) {
            $existing = null;
            if ($existingSalon) {
                $existing = Salon::lockForUpdate()->findOrFail($existingSalon->id);

                if (! in_array($existing->status, self::EDITABLE_STATUSES, true)) {
                    return ['salon' => $existing->load('city:id,name,state'), 'created' => false, 'resubmitted' => false];
                }
            }

            $owner = $this->resolveOwner(null, $payload);

            if (! $existing) {
                // Deduplication guard: if this collaborator already created a salon for this
                // owner with the same name that is pending approval or in an editable state,
                // reuse and revise that salon rather than creating a duplicate.
                $existing = Salon::where('submitted_by', $collaborator->id)
                    ->where('admin_id', $owner->id)
                    ->whereRaw('LOWER(TRIM(name)) = ?', [mb_strtolower(trim($payload['salon_name']))])
                    ->whereIn('status', self::EDITABLE_STATUSES)
                    ->lockForUpdate()
                    ->first();
            }

            $salon = $existing
                ? $this->reviseSalon($existing, $owner, $payload)
                : $this->createSalonDirect($collaborator, $owner, $payload);

            $this->writeWorkingHours($salon, $payload['working_hours'] ?? []);
            if (array_key_exists('services', $payload)) {
                $this->writeServices($salon, $payload['services'] ?? [], true);
            }
            $this->storePhotos($salon, $collaborator, $photos, (int) ($payload['cover_index'] ?? 0));

            return [
                'salon' => $salon->fresh()->load('city:id,name,state'),
                'created' => ! $existing,
                'resubmitted' => (bool) $existing,
            ];
        });
    }

    /**
     * The owner's account.
     *
     * Partner sign-in is a phone and an OTP, so the phone is the identity and
     * the password is never used. An owner who already has an account keeps it
     * — a collaborator onboarding their second salon must not be handed a
     * duplicate user.
     */
    private function resolveOwner(?SalonEnquiry $enquiry, array $payload): User
    {
        $phone = $payload['owner_phone'] ?? $enquiry?->phone;
        $existing = User::where('phone', $phone)->first();

        if ($existing) {
            if ($existing->role !== 'admin') {
                throw new \RuntimeException(
                    "{$phone} already belongs to a {$existing->role} account and cannot own a salon."
                );
            }

            return $existing;
        }

        return User::create([
            'role' => 'admin',
            'name' => $payload['owner_name'] ?? $enquiry?->owner_name,
            'phone' => $phone,
            'email' => $payload['owner_email'] ?? null,
            // Never used to sign in; present because the column demands it.
            'password_hash' => Hash::make(Str::random(32)),
        ]);
    }

    private function createSalon(SalonEnquiry $enquiry, User $collaborator, User $owner, array $payload): Salon
    {
        return Salon::create($this->salonAttributes($payload) + [
            'admin_id' => $owner->id,
            'slug' => $this->uniqueSlug($payload['salon_name']),
            'enquiry_id' => $enquiry->id,
            'submitted_by' => $collaborator->id,
            'assigned_collaborator_id' => $collaborator->id,
            'status' => 'pending_approval',
            'advance_required' => true,
            'advance_refundable' => false,
            'advance_percentage_default' => 25.00,
        ]);
    }

    private function createSalonDirect(User $collaborator, User $owner, array $payload): Salon
    {
        return Salon::create($this->salonAttributes($payload) + [
            'admin_id' => $owner->id,
            'slug' => $this->uniqueSlug($payload['salon_name']),
            'enquiry_id' => null,
            'submitted_by' => $collaborator->id,
            'assigned_collaborator_id' => $collaborator->id,
            'status' => 'pending_approval',
            'advance_required' => true,
            'advance_refundable' => false,
            'advance_percentage_default' => 25.00,
        ]);
    }

    /**
     * An edit to a salon that has not been approved yet — either a correction
     * SuperAdmin asked for, or the collaborator fixing something themselves
     * while it sits in the queue.
     *
     * The same salon goes round again rather than a new one being made, so its
     * id, and anything already pointing at it, survives the change.
     */
    private function reviseSalon(Salon $salon, User $owner, array $payload): Salon
    {
        $salon->update($this->salonAttributes($payload) + [
            'admin_id' => $owner->id,
            'status' => 'pending_approval',
            'rejection_reason' => null,
            'correction_notes' => null,
            'resubmitted_at' => now(),
        ]);

        return $salon;
    }

    /** @return array<string, mixed> */
    private function salonAttributes(array $payload): array
    {
        $hasPin = isset($payload['latitude'], $payload['longitude']);
        $preferredModel = $payload['preferred_commercial_model'] ?? 'subscription';
        $requestedComm = ($preferredModel === 'commission' && isset($payload['requested_commission_percentage']))
            ? $payload['requested_commission_percentage']
            : null;

        return [
            'name' => $payload['salon_name'],
            'description' => $payload['description'] ?? null,
            'address' => $payload['address'],
            'city_id' => $payload['city_id'],
            'sub_area_id' => $payload['sub_area_id'] ?? null,
            'pincode' => $payload['pincode'] ?? null,
            // The salon's own line, taken on site by the collaborator. Never
            // shown to customers.
            'phone_num' => $payload['salon_phone'] ?? null,
            'gender_focus' => $payload['gender_focus'] ?? 'Unisex',
            'latitude' => $payload['latitude'] ?? null,
            'longitude' => $payload['longitude'] ?? null,
            // A collaborator pins the salon from inside it, which is the same
            // quality of answer as the owner doing it.
            'location_source' => $hasPin ? 'owner' : null,
            'preferred_plan_id' => $payload['preferred_plan_id'] ?? null,
            'preferred_commercial_model' => $preferredModel,
            'requested_commission_percentage' => $requestedComm,
        ];
    }

    private function uniqueSlug(string $name): string
    {
        $base = Str::slug($name) ?: 'salon';
        $slug = $base;

        while (Salon::where('slug', $slug)->exists()) {
            $slug = $base . '-' . Str::lower(Str::random(6));
        }

        return $slug;
    }

    /**
     * A day absent from the submission is closed, not unchanged — the
     * collaborator's form is the complete week, so the days missing from it are
     * removed rather than left holding last submission's times.
     *
     * The days that *are* submitted are keyed updates rather than inserts. A
     * repeated submission has to be a no-op rather than a collision: the
     * (salon_id, day_of_week) unique index means an insert would fail the
     * moment the row was already there, which is exactly what happened when two
     * submissions overlapped.
     *
     * @param  array<int, array<string, mixed>>  $days
     */
    private function writeWorkingHours(Salon $salon, array $days): void
    {
        if (empty($days)) {
            return;
        }

        // Keyed by day so a payload listing the same day twice cannot insert it
        // twice within one request and trip its own constraint. Later entry
        // wins, matching how the form renders one row per day.
        $byDay = [];

        foreach ($days as $day) {
            $byDay[(int) $day['day_of_week']] = $day;
        }

        SalonWorkingHour::where('salon_id', $salon->id)
            ->whereNotIn('day_of_week', array_keys($byDay))
            ->delete();

        foreach ($byDay as $dayOfWeek => $day) {
            $closed = filter_var($day['is_closed'] ?? false, FILTER_VALIDATE_BOOLEAN);

            SalonWorkingHour::updateOrCreate(
                ['salon_id' => $salon->id, 'day_of_week' => $dayOfWeek],
                [
                    'is_closed' => $closed,
                    'open_time' => $closed ? null : ($day['open_time'] ?? null),
                    'close_time' => $closed ? null : ($day['close_time'] ?? null),
                ]
            );
        }
    }

    /**
     * Services are optional — a salon can be submitted as a profile alone and
     * have its menu filled in by the owner later.
     *
     * @param  array<int, array<string, mixed>>  $services
     */
    private function writeServices(Salon $salon, array $services, bool $reconcile = true): void
    {
        $activeTemplateIds = [];

        foreach ($services as $index => $line) {
            $templateId = $this->resolveTemplate($salon, $line);
            $activeTemplateIds[] = $templateId;

            $attributes = [
                'price' => (float) $line['price'],
                'description' => $line['description'] ?? null,
                'advance_percentage' => $line['advance_percentage'] ?? null,
                'gender_focus' => $line['gender_focus'] ?? $salon->gender_focus,
                'is_active' => true,
                'display_order' => $index,
            ];

            // Handle existing rows safely including soft-deleted ones
            $existingService = Service::withTrashed()
                ->where('salon_id', $salon->id)
                ->where('template_id', $templateId)
                ->first();

            if ($existingService) {
                if ($existingService->trashed()) {
                    $existingService->restore();
                }
                $existingService->update($attributes);
            } else {
                try {
                    Service::create(array_merge([
                        'salon_id' => $salon->id,
                        'template_id' => $templateId,
                    ], $attributes));
                } catch (\Illuminate\Database\QueryException $e) {
                    $winner = Service::withTrashed()
                        ->where('salon_id', $salon->id)
                        ->where('template_id', $templateId)
                        ->first();
                    if ($winner) {
                        if ($winner->trashed()) {
                            $winner->restore();
                        }
                        $winner->update($attributes);
                    } else {
                        throw $e;
                    }
                }
            }
        }

        // Reconcile omitted services during editable onboarding submission:
        // Soft-delete any services for this salon that are active but not in the submitted list.
        if ($reconcile) {
            Service::where('salon_id', $salon->id)
                ->whereNotIn('template_id', $activeTemplateIds)
                ->delete();
        }
    }

    /**
     * Either a pick from the master catalog or something this salon does that
     * the catalog has never heard of, in which case it gets its own template
     * exactly as the admin app would create one.
     */
    private function resolveTemplate(Salon $salon, array $line): string
    {
        if (! empty($line['template_id'])) {
            return $line['template_id'];
        }

        $name = trim($line['custom_template_name'] ?? '');
        $duration = (int) ($line['estimated_duration_minutes'] ?? 30);
        $categoryId = $line['category_id'] ?? null;

        // 1. Resolve Category
        if ($categoryId === 'new_custom' || empty($categoryId)) {
            $rawCatName = trim($line['custom_category_name'] ?? 'Other');
            $catName = $rawCatName !== '' ? $rawCatName : 'Other';

            // Look for existing category owned by this salon, or standard category with exact matching name
            $existingCat = ServiceCategory::where('created_by_salon_id', $salon->id)
                ->whereRaw('LOWER(name) = ?', [mb_strtolower($catName)])
                ->first();

            if (! $existingCat) {
                $existingCat = ServiceCategory::where('is_custom', false)
                    ->whereRaw('LOWER(name) = ?', [mb_strtolower($catName)])
                    ->first();
            }

            if ($existingCat) {
                $categoryId = $existingCat->id;
            } else {
                try {
                    $categoryId = ServiceCategory::create([
                        'name' => $catName,
                        'is_custom' => true,
                        'created_by_salon_id' => $salon->id,
                    ])->id;
                } catch (\Illuminate\Database\QueryException $e) {
                    $winnerCat = ServiceCategory::where('created_by_salon_id', $salon->id)
                        ->whereRaw('LOWER(name) = ?', [mb_strtolower($catName)])
                        ->first();
                    if ($winnerCat) {
                        $categoryId = $winnerCat->id;
                    } else {
                        throw $e;
                    }
                }
            }
        }

        // 2. Resolve Custom Template: reuse existing custom template owned by this salon
        // Match by created_by_salon_id = $salon->id, is_custom = true, category_id = $categoryId, and normalized name
        $existingTemplate = ServiceTemplate::where('created_by_salon_id', $salon->id)
            ->where('is_custom', true)
            ->where('category_id', $categoryId)
            ->whereRaw('LOWER(TRIM(name)) = ?', [mb_strtolower($name)])
            ->first();

        if ($existingTemplate) {
            $existingTemplate->update([
                'estimated_duration_minutes' => $duration >= 15 ? $duration : $existingTemplate->estimated_duration_minutes,
                'is_active' => true,
            ]);

            return $existingTemplate->id;
        }

        try {
            return ServiceTemplate::create([
                'category_id' => $categoryId,
                'name' => $name,
                'estimated_duration_minutes' => $duration >= 15 ? $duration : 30,
                'is_custom' => true,
                'created_by_salon_id' => $salon->id,
                'is_active' => true,
            ])->id;
        } catch (\Illuminate\Database\QueryException $e) {
            $winnerTemplate = ServiceTemplate::where('created_by_salon_id', $salon->id)
                ->where('is_custom', true)
                ->where('category_id', $categoryId)
                ->whereRaw('LOWER(TRIM(name)) = ?', [mb_strtolower($name)])
                ->first();
            if ($winnerTemplate) {
                return $winnerTemplate->id;
            }
            throw $e;
        }
    }

    /**
     * Photos arrive only on the attempt that had signal to carry them, so an
     * empty set leaves whatever is already there alone.
     *
     * @param  UploadedFile[]  $photos
     */
    private function storePhotos(Salon $salon, User $collaborator, array $photos, int $coverIndex): void
    {
        if (empty($photos)) {
            return;
        }

        // A resubmission sends the full set again; keeping the old rows would
        // leave the gallery holding photos the collaborator deleted.
        SalonMedia::where('salon_id', $salon->id)->delete();

        $coverUrl = null;

        foreach (array_values($photos) as $index => $photo) {
            $path = $photo->storeAs(
                self::PHOTO_DIR,
                Str::uuid() . '.' . ($photo->getClientOriginalExtension() ?: 'jpg'),
                'public'
            );

            $url = asset('storage/' . $path);
            $isCover = $index === $coverIndex;

            SalonMedia::create([
                'salon_id' => $salon->id,
                'media_type' => 'image',
                'file_url' => $url,
                'sort_order' => $index,
                'is_cover' => $isCover,
                'uploaded_by' => $collaborator->id,
            ]);

            if ($isCover) {
                $coverUrl = $url;
            }
        }

        // The cover is denormalised onto the salon because every list view
        // needs it and none of them should have to join the gallery.
        $salon->update(['cover_photo_url' => $coverUrl ?? asset('storage/' . $path)]);
    }
}
