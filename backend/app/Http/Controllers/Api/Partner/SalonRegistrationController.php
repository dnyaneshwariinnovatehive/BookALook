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
        $isExistingAdmin = auth('sanctum')->check();
        
        $request->validate([
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

            // Photos (Optional during self-registration)
            'photos' => 'nullable|array|max:10',
            'photos.*' => 'image|mimes:jpeg,png,jpg,webp|max:5120',
            'cover_image' => 'nullable|image|mimes:jpeg,png,jpg,webp|max:5120',
            'cover_index' => 'nullable|integer|min:0',
        ]);

        try {
            DB::beginTransaction();

            if ($isExistingAdmin) {
                $adminUser = $request->user();
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

            // 3. Generate unique slug for Salon
            $slug = Str::slug($request->salon_name);
            if (Salon::where('slug', $slug)->exists()) {
                $slug = $slug . '-' . uniqid();
            }

            // 4. Create the Salon
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
                // Only the owner standing in their own salon can claim 'owner'.
                'location_source' => $request->filled(['latitude', 'longitude'])
                    ? 'owner'
                    : null,
                'status' => 'pending_approval',
                'submitted_by' => $adminUser->id,
                'advance_required' => true,
                'advance_refundable' => false,
                'advance_percentage_default' => 25.00,
                'gender_focus' => $request->gender_focus ?? 'Unisex',
            ]);

            // 5. Store Photos if provided
            $uploadedPhotos = [];
            if ($request->hasFile('photos')) {
                $uploadedPhotos = $request->file('photos');
            } elseif ($request->hasFile('cover_image')) {
                $uploadedPhotos = [$request->file('cover_image')];
            }

            $coverIndex = (int) ($request->input('cover_index') ?? 0);
            $coverUrl = null;

            if (!empty($uploadedPhotos)) {
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

            return response()->json([
                'message' => 'Salon registered successfully. Pending SuperAdmin approval.',
                'user' => $adminUser,
                'salon' => $salon->fresh()->load('media')
            ], 201);

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
}
