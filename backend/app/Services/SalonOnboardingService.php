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
    private const EDITABLE_STATUSES = ['pending_approval', 'rejected'];

    /**
     * @param  array<string, mixed>  $payload
     * @param  UploadedFile[]  $photos
     * @return array{salon: Salon, created: bool, resubmitted: bool}
     */
    public function onboard(SalonEnquiry $enquiry, User $collaborator, array $payload, array $photos = []): array
    {
        $existing = $enquiry->salon()->first();

        // Approved, suspended or deactivated: the collaborator is done here.
        // Also the landing spot for a retried submission of a salon that has
        // since gone live, which must not be rewritten by a stale draft.
        if ($existing && ! in_array($existing->status, self::EDITABLE_STATUSES, true)) {
            return ['salon' => $existing->load('city:id,name,state'), 'created' => false, 'resubmitted' => false];
        }

        $owner = $this->resolveOwner($enquiry, $payload);

        return DB::transaction(function () use ($enquiry, $collaborator, $payload, $photos, $existing, $owner) {
            $salon = $existing
                ? $this->reviseSalon($existing, $owner, $payload)
                : $this->createSalon($enquiry, $collaborator, $owner, $payload);

            $this->writeWorkingHours($salon, $payload['working_hours'] ?? []);
            $this->writeServices($salon, $payload['services'] ?? []);
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
     * The owner's account.
     *
     * Partner sign-in is a phone and an OTP, so the phone is the identity and
     * the password is never used. An owner who already has an account keeps it
     * — a collaborator onboarding their second salon must not be handed a
     * duplicate user.
     */
    private function resolveOwner(SalonEnquiry $enquiry, array $payload): User
    {
        $phone = $payload['owner_phone'] ?? $enquiry->phone;
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
            'name' => $payload['owner_name'] ?? $enquiry->owner_name,
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
        ]);

        return $salon;
    }

    /** @return array<string, mixed> */
    private function salonAttributes(array $payload): array
    {
        $hasPin = isset($payload['latitude'], $payload['longitude']);

        return [
            'name' => $payload['salon_name'],
            'description' => $payload['description'] ?? null,
            'address' => $payload['address'],
            'city_id' => $payload['city_id'],
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
     * Replaced wholesale rather than merged: the submission is the complete
     * week, and a day missing from it means closed, not unchanged.
     *
     * @param  array<int, array<string, mixed>>  $days
     */
    private function writeWorkingHours(Salon $salon, array $days): void
    {
        if (empty($days)) {
            return;
        }

        SalonWorkingHour::where('salon_id', $salon->id)->delete();

        foreach ($days as $day) {
            $closed = filter_var($day['is_closed'] ?? false, FILTER_VALIDATE_BOOLEAN);

            SalonWorkingHour::create([
                'salon_id' => $salon->id,
                'day_of_week' => (int) $day['day_of_week'],
                'is_closed' => $closed,
                'open_time' => $closed ? null : ($day['open_time'] ?? null),
                'close_time' => $closed ? null : ($day['close_time'] ?? null),
            ]);
        }
    }

    /**
     * Services are optional — a salon can be submitted as a profile alone and
     * have its menu filled in by the owner later.
     *
     * @param  array<int, array<string, mixed>>  $services
     */
    private function writeServices(Salon $salon, array $services): void
    {
        foreach ($services as $index => $line) {
            $templateId = $this->resolveTemplate($salon, $line);

            // The salon/template pair is unique, so a resubmission updates the
            // price rather than colliding with the row it wrote last time.
            Service::updateOrCreate(
                ['salon_id' => $salon->id, 'template_id' => $templateId],
                [
                    'price' => (float) $line['price'],
                    'description' => $line['description'] ?? null,
                    'advance_percentage' => $line['advance_percentage'] ?? null,
                    'gender_focus' => $line['gender_focus'] ?? $salon->gender_focus,
                    'is_active' => true,
                    'display_order' => $index,
                ]
            );
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

        $categoryId = $line['category_id'] ?? null;

        if ($categoryId === 'new_custom' || empty($categoryId)) {
            $categoryId = ServiceCategory::create([
                'name' => $line['custom_category_name'] ?? 'Other',
                'is_custom' => true,
                'created_by_salon_id' => $salon->id,
            ])->id;
        }

        return ServiceTemplate::create([
            'category_id' => $categoryId,
            'name' => $line['custom_template_name'],
            'estimated_duration_minutes' => (int) $line['estimated_duration_minutes'],
            'is_custom' => true,
            'created_by_salon_id' => $salon->id,
        ])->id;
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
