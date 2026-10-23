<?php

namespace App\Http\Controllers\Api\Partner;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\User;
use App\Models\Salon;
use App\Models\SalonMedia;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class SalonRegistrationController extends Controller
{
    public function register(Request $request)
    {
        $authenticatedUser = $request->user('sanctum') ?: auth('sanctum')->user();
        $isExistingAdmin = ($authenticatedUser !== null && in_array($authenticatedUser->role, ['admin', 'salon_owner'], true));

        if ($authenticatedUser && ! $isExistingAdmin) {
            return response()->json([
                'message' => 'Only admin accounts can register or manage a salon.',
            ], 403);
        }
        
        $request->validate([
            // Editing existing salon application
            'salon_id' => 'nullable|uuid|exists:salons,id',

            // Owner Account Details
            'full_name' => $isExistingAdmin ? 'nullable' : 'required|string|max:150',
            'email' => $isExistingAdmin ? 'nullable' : 'required|email|max:150',
            'phone_number' => $isExistingAdmin ? 'nullable' : 'required|string|max:15',
            'password' => $isExistingAdmin ? 'nullable' : 'required|string|min:6',
            
            // Salon Details
            'salon_name' => 'required|string|max:150',
            'description' => 'nullable|string',
            'street_address' => 'required|string',
            'city_id' => 'required|exists:cities,id',
            // The locality. Customers browse by it and collaborators are
            // matched on it, so a salon without one is invisible to both.
            'sub_area_id' => [
                'required', 'uuid',
                \Illuminate\Validation\Rule::exists('sub_areas', 'id')->where(
                    fn ($q) => $q->where('city_id', $request->city_id)
                ),
            ],
            'pincode' => 'required|string|max:10',
            // Optional: an owner registering from a laptop at home should not
            // be blocked, and they can drop the pin later from the app.
            'latitude' => 'nullable|numeric|between:-90,90',
            'longitude' => 'nullable|numeric|between:-180,180',
            'gender_focus' => 'nullable|string', // Appended to description

            // Commercial Model & Plan Preferences
            'preferred_plan_id' => 'nullable|uuid|exists:subscription_plans,id',
            'preferred_commercial_model' => 'nullable|in:subscription,commission',
            'requested_commission_percentage' => 'nullable|required_if:preferred_commercial_model,commission|numeric|min:0|max:100',

            // Photos (Mandatory main cover photo required)
            'photos' => 'nullable|array|max:10',
            'photos.*' => 'image|mimes:jpeg,png,jpg,webp|max:5120',
            'cover_image' => 'nullable|image|mimes:jpeg,png,jpg,webp|max:5120',
            'cover_index' => 'nullable|integer|min:0',
            'cover_photo_index' => 'nullable|integer|min:0',
        ]);

        try {
            DB::beginTransaction();

            if ($isExistingAdmin) {
                $adminUser = $authenticatedUser;
            } else {
                // 1. Find or Create the Admin User
                $adminUser = User::where('email', $request->email)
                    ->orWhere('phone', $request->phone_number)
                    ->first();

                if ($adminUser) {
                    if ($adminUser->role !== 'admin') {
                        throw ValidationException::withMessages(['email' => 'This account exists but is not an admin account.']);
                    }
                    if (!Hash::check($request->password, $adminUser->password_hash)) {
                        throw ValidationException::withMessages(['password' => 'Incorrect password for existing account.']);
                    }
                    // Verify both email and phone match the existing account to prevent hijacking someone else's phone/email
                    if ($adminUser->email !== $request->email || $adminUser->phone !== $request->phone_number) {
                        throw ValidationException::withMessages(['email' => 'Email and phone number do not match the existing account.']);
                    }
                } else {
                    $adminUser = User::create([
                        'role' => 'admin',
                        'name' => $request->full_name,
                        'email' => $request->email,
                        'phone' => $request->phone_number,
                        'password_hash' => Hash::make($request->password),
                    ]);
                }
            }

            // 2. Format Address & Description
            $fullAddress = $request->street_address;
            $fullDescription = $request->description ?? '';

            // 3. Resolve Photos & Mandatory Cover Photo
            $uploadedPhotos = [];
            if ($request->hasFile('photos')) {
                $uploadedPhotos = $request->file('photos');
            } elseif ($request->hasFile('cover_image')) {
                $uploadedPhotos = [$request->file('cover_image')];
            }

            $coverIndex = (int) ($request->input('cover_index') ?? $request->input('cover_photo_index') ?? 0);
            if (!empty($uploadedPhotos) && $coverIndex >= count($uploadedPhotos)) {
                $coverIndex = 0;
            }

            // 4. Create or Revise Salon
            $preferredModel = $request->input('preferred_commercial_model', 'subscription');
            $requestedComm = ($preferredModel === 'commission') ? $request->input('requested_commission_percentage') : null;

            if ($request->filled('salon_id')) {
                $salon = Salon::where('id', $request->salon_id)
                    ->where('admin_id', $adminUser->id)
                    ->first();

                if (! $salon) {
                    throw ValidationException::withMessages(['salon_id' => 'Salon not found or does not belong to you.']);
                }

                if (! in_array($salon->status, ['pending_approval', 'rejected', 'needs_correction'], true)) {
                    throw ValidationException::withMessages(['salon_id' => 'Approved salons cannot be edited through registration.']);
                }

                // If no new photos uploaded, verify existing salon has a cover photo
                if (empty($uploadedPhotos) && empty($salon->cover_photo_url)) {
                    throw ValidationException::withMessages(['cover_photo' => 'A main cover photo is mandatory for salon registration.']);
                }

                $salon->update([
                    'name' => $request->salon_name,
                    'description' => trim($fullDescription),
                    'city_id' => $request->city_id,
                    'sub_area_id' => $request->sub_area_id,
                    'address' => $fullAddress,
                    'pincode' => $request->pincode,
                    'latitude' => $request->latitude,
                    'longitude' => $request->longitude,
                    'location_source' => $request->filled(['latitude', 'longitude']) ? 'owner' : $salon->location_source,
                    'gender_focus' => $request->gender_focus ?? 'Unisex',
                    'preferred_plan_id' => ($preferredModel === 'subscription') ? $request->preferred_plan_id : null,
                    'preferred_commercial_model' => $preferredModel,
                    'requested_commission_percentage' => $requestedComm,
                    'status' => 'pending_approval',
                    'rejection_reason' => null,
                    'correction_notes' => null,
                    'resubmitted_at' => now(),
                ]);
            } else {
                if (empty($uploadedPhotos)) {
                    throw ValidationException::withMessages(['cover_photo' => 'A main cover photo is mandatory for salon registration.']);
                }

                $slug = Str::slug($request->salon_name);
                if (Salon::where('slug', $slug)->exists()) {
                    $slug = $slug . '-' . uniqid();
                }

                $salon = Salon::create([
                    'admin_id' => $adminUser->id,
                    'name' => $request->salon_name,
                    'slug' => $slug,
                    'description' => trim($fullDescription),
                    'city_id' => $request->city_id,
                    'sub_area_id' => $request->sub_area_id,
                    'address' => $fullAddress,
                    'pincode' => $request->pincode,
                    'latitude' => $request->latitude,
                    'longitude' => $request->longitude,
                    'location_source' => $request->filled(['latitude', 'longitude']) ? 'owner' : null,
                    'status' => 'pending_approval',
                    'submitted_by' => $adminUser->id,
                    'advance_required' => true,
                    'advance_refundable' => false,
                    'advance_percentage_default' => 25.00,
                    'gender_focus' => $request->gender_focus ?? 'Unisex',
                    'preferred_plan_id' => ($preferredModel === 'subscription') ? $request->preferred_plan_id : null,
                    'preferred_commercial_model' => $preferredModel,
                    'requested_commission_percentage' => $requestedComm,
                ]);
            }

            // 5. Store Photos if provided
            if (!empty($uploadedPhotos)) {
                // If replacing photos on revision, clean up old records
                SalonMedia::where('salon_id', $salon->id)->delete();

                $coverUrl = null;
                foreach (array_values($uploadedPhotos) as $index => $photo) {
                    $path = $photo->storeAs(
                        'salons',
                        Str::uuid() . '.' . ($photo->getClientOriginalExtension() ?: 'jpg'),
                        'public'
                    );

                    $url = asset('storage/' . $path);
                    $isCover = ($index === $coverIndex);

                    SalonMedia::create([
                        'salon_id' => $salon->id,
                        'media_type' => 'image',
                        'file_url' => $url,
                        'sort_order' => $index,
                        'is_cover' => $isCover,
                        'uploaded_by' => $adminUser->id,
                    ]);

                    if ($isCover || $coverUrl === null) {
                        $coverUrl = $url;
                    }
                }

                if ($coverUrl) {
                    $salon->update(['cover_photo_url' => $coverUrl]);
                }
            }

            DB::commit();

            $statusCode = $request->filled('salon_id') ? 200 : 201;
            $message = $request->filled('salon_id')
                ? 'Salon application resubmitted successfully. Pending SuperAdmin approval.'
                : 'Salon registered successfully. Pending SuperAdmin approval.';

            $allSalons = Salon::with(['city:id,name', 'admin:id,name,phone', 'media'])
                ->where('admin_id', $adminUser->id)
                ->orderBy('created_at', 'desc')
                ->get();

            $token = null;
            if (! $isExistingAdmin) {
                $token = $adminUser->createToken('partner-auth-token')->plainTextToken;
            }

            return response()->json([
                'message' => $message,
                'user' => $adminUser,
                'salon' => $salon->fresh()->load(['media', 'city:id,name']),
                'salons' => $allSalons,
                'token' => $token,
            ], $statusCode);

        } catch (\Illuminate\Validation\ValidationException $e) {
            DB::rollBack();
            throw $e;
        } catch (\Exception $e) {
            DB::rollBack();
            return response()->json([
                'message' => 'Failed to register salon.',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Retrieve all salons owned by the authenticated admin.
     */
    public function mySalons(Request $request)
    {
        $user = $request->user('sanctum') ?: auth('sanctum')->user();
        if (! $user || ! in_array($user->role, ['admin', 'salon_owner'], true)) {
            return response()->json([
                'success' => false,
                'message' => 'Unauthorized or not an admin account.',
            ], 403);
        }

        $salons = Salon::with(['city:id,name', 'admin:id,name,phone', 'media'])
            ->where('admin_id', $user->id)
            ->orderBy('created_at', 'desc')
            ->get();

        return response()->json([
            'success' => true,
            'salons' => $salons,
        ]);
    }
}
