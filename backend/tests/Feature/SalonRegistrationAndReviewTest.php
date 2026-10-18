<?php

namespace Tests\Feature;

use App\Models\City;
use App\Models\Salon;
use App\Models\SalonMedia;
use App\Models\SalonSubscription;
use App\Models\SalonWorkingHour;
use App\Models\SubArea;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Models\WalletTransaction;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class SalonRegistrationAndReviewTest extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
    }

    public function test_registration_requires_cover_photo_and_rejects_empty(): void
    {
        $city = City::first() ?? City::create(['name' => 'Pune', 'state' => 'Maharashtra', 'is_active' => true]);
        $subArea = SubArea::first() ?? SubArea::create(['city_id' => $city->id, 'name' => 'Koregaon Park']);

        $payload = [
            'full_name' => 'Anita Desai',
            'email' => 'anita' . uniqid() . '@example.com',
            'phone_number' => '98765' . rand(10000, 99999),
            'password' => 'secret123',
            'salon_name' => 'Anita Glamour Hub',
            'street_address' => 'Shop 12, Main Street',
            'city_id' => $city->id,
            'sub_area_id' => $subArea->id,
            'pincode' => '411001',
            'gender_focus' => 'Women Only',
            'preferred_commercial_model' => 'subscription',
        ];

        // Submission with no photos or cover photo must be rejected with 422
        $response = $this->postJson('/api/partner/register', $payload);
        $response->assertStatus(422)
            ->assertJsonValidationErrors(['cover_photo']);
    }

    public function test_registration_saves_commercial_preferences_and_cover_photo(): void
    {
        $city = City::first() ?? City::create(['name' => 'Pune', 'state' => 'Maharashtra', 'is_active' => true]);
        $subArea = SubArea::first() ?? SubArea::create(['city_id' => $city->id, 'name' => 'Koregaon Park']);
        $plan = SubscriptionPlan::first() ?? SubscriptionPlan::create([
            'name' => 'Starter Plan',
            'price' => 999,
            'duration_days' => 30,
            'is_active' => true,
        ]);

        $photo1 = UploadedFile::fake()->create('front.jpg', 100, 'image/jpeg');
        $photo2 = UploadedFile::fake()->create('interior.jpg', 100, 'image/jpeg');

        $payload = [
            'full_name' => 'Rahul Sharma',
            'email' => 'rahul' . uniqid() . '@example.com',
            'phone_number' => '98888' . rand(10000, 99999),
            'password' => 'secret123',
            'salon_name' => 'Rahul Hair Studio',
            'description' => 'Top styling and cuts',
            'street_address' => 'FC Road, Lane 4',
            'city_id' => $city->id,
            'sub_area_id' => $subArea->id,
            'pincode' => '411004',
            'gender_focus' => 'Unisex',
            'preferred_plan_id' => $plan->id,
            'preferred_commercial_model' => 'commission',
            'requested_commission_percentage' => '15.50',
            'photos' => [$photo1, $photo2],
            'cover_index' => 1, // Second photo is cover
        ];

        $response = $this->post('/api/partner/register', $payload);
        $response->assertStatus(201);

        $createdSalon = Salon::where('name', 'Rahul Hair Studio')->latest()->first();
        $this->assertNotNull($createdSalon);
        $this->assertEquals('pending_approval', $createdSalon->status);
        $this->assertEquals($plan->id, $createdSalon->preferred_plan_id);
        $this->assertEquals('commission', $createdSalon->preferred_commercial_model);
        $this->assertEquals('15.50', (string) $createdSalon->requested_commission_percentage);
        $this->assertNotNull($createdSalon->cover_photo_url);

        // Check media table: exactly one photo is cover
        $media = SalonMedia::where('salon_id', $createdSalon->id)->get();
        $this->assertCount(2, $media);
        $covers = $media->where('is_cover', true);
        $this->assertCount(1, $covers);
    }

    public function test_registration_rejects_invalid_commission_percentage(): void
    {
        $city = City::first() ?? City::create(['name' => 'Pune', 'state' => 'Maharashtra', 'is_active' => true]);
        $subArea = SubArea::first() ?? SubArea::create(['city_id' => $city->id, 'name' => 'Koregaon Park']);
        $photo = UploadedFile::fake()->create('front.jpg', 100, 'image/jpeg');

        $payload = [
            'full_name' => 'Suresh Patil',
            'email' => 'suresh' . uniqid() . '@example.com',
            'phone_number' => '97777' . rand(10000, 99999),
            'password' => 'secret123',
            'salon_name' => 'Suresh Salon',
            'street_address' => 'MG Road',
            'city_id' => $city->id,
            'sub_area_id' => $subArea->id,
            'pincode' => '411001',
            'preferred_commercial_model' => 'commission',
            'requested_commission_percentage' => '120.00', // Invalid: > 100
            'photos' => [$photo],
        ];

        $response = $this->postJson('/api/partner/register', $payload);
        $response->assertStatus(422)
            ->assertJsonValidationErrors(['requested_commission_percentage']);
    }

    public function test_superadmin_review_returns_complete_salon_details(): void
    {
        $city = City::first() ?? City::create(['name' => 'Pune', 'state' => 'Maharashtra', 'is_active' => true]);
        $subArea = SubArea::first() ?? SubArea::create(['city_id' => $city->id, 'name' => 'Koregaon Park']);
        $owner = User::create([
            'name' => 'Vikram Rao',
            'phone' => '96666' . rand(10000, 99999),
            'email' => 'vikram' . uniqid() . '@example.com',
            'password_hash' => 'x',
            'role' => 'salon_owner',
            'is_active' => true,
        ]);
        $collaborator = User::create([
            'name' => 'Collab John',
            'phone' => '95555' . rand(10000, 99999),
            'email' => 'john' . uniqid() . '@example.com',
            'password_hash' => 'x',
            'role' => 'collaborator',
            'is_active' => true,
        ]);
        $plan = SubscriptionPlan::first() ?? SubscriptionPlan::create([
            'name' => 'Pro Plan',
            'price' => 1999,
            'duration_days' => 60,
            'is_active' => true,
        ]);

        $salon = Salon::create([
            'name' => 'Vikram Grooming',
            'slug' => 'vikram-grooming-' . uniqid(),
            'admin_id' => $owner->id,
            'submitted_by' => $owner->id,
            'city_id' => $city->id,
            'sub_area_id' => $subArea->id,
            'assigned_collaborator_id' => $collaborator->id,
            'address' => 'Baner High Street',
            'pincode' => '411045',
            'status' => 'pending_approval',
            'preferred_plan_id' => $plan->id,
            'preferred_commercial_model' => 'commission',
            'requested_commission_percentage' => '12.00',
            'cover_photo_url' => 'https://example.com/cover.jpg',
        ]);

        SalonMedia::create([
            'salon_id' => $salon->id,
            'media_type' => 'image',
            'file_url' => 'https://example.com/cover.jpg',
            'is_cover' => true,
            'uploaded_by' => $owner->id,
        ]);

        SalonWorkingHour::create([
            'salon_id' => $salon->id,
            'day_of_week' => 1,
            'open_time' => '10:00',
            'close_time' => '20:00',
            'is_closed' => false,
        ]);

        $response = $this->getJson("/api/superadmin/salons/pending/{$salon->id}");
        $response->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.name', 'Vikram Grooming')
            ->assertJsonPath('data.preferred_commercial_model', 'commission')
            ->assertJsonPath('data.requested_commission_percentage', '12.00')
            ->assertJsonPath('data.preferred_plan.name', $plan->name)
            ->assertJsonPath('data.assigned_collaborator.name', 'Collab John')
            ->assertJsonPath('data.sub_area.name', 'Koregaon Park')
            ->assertJsonPath('data.media.0.is_cover', true)
            ->assertJsonPath('data.working_hours.0.day_of_week', 1);
    }

    public function test_superadmin_approval_requires_commission_rate_for_commission_model(): void
    {
        $city = City::first() ?? City::create(['name' => 'Pune', 'state' => 'Maharashtra', 'is_active' => true]);
        $owner = User::create([
            'name' => 'Owner ' . uniqid(),
            'phone' => '94444' . rand(10000, 99999),
            'password_hash' => 'x',
            'role' => 'salon_owner',
            'is_active' => true,
        ]);

        $salon = Salon::create([
            'name' => 'Commission Salon ' . uniqid(),
            'slug' => 'comm-salon-' . uniqid(),
            'admin_id' => $owner->id,
            'submitted_by' => $owner->id,
            'city_id' => $city->id,
            'address' => 'MG Road',
            'pincode' => '411001',
            'status' => 'pending_approval',
            'preferred_commercial_model' => 'commission',
            'requested_commission_percentage' => '15.00',
        ]);

        // Attempt approve without specifying final commission rate -> 422
        $response = $this->postJson("/api/superadmin/salons/{$salon->id}/approve", [
            'commercial_model' => 'commission',
        ]);
        $response->assertStatus(422)
            ->assertJsonValidationErrors(['commission_percentage']);
    }

    public function test_superadmin_approval_sets_authoritative_rate_and_awards_welcome_bonus_idempotently(): void
    {
        $city = City::first() ?? City::create(['name' => 'Pune', 'state' => 'Maharashtra', 'is_active' => true]);
        $owner = User::create([
            'name' => 'Owner ' . uniqid(),
            'phone' => '93333' . rand(10000, 99999),
            'password_hash' => 'x',
            'role' => 'salon_owner',
            'is_active' => true,
        ]);

        $salon = Salon::create([
            'name' => 'Approved Comm Salon ' . uniqid(),
            'slug' => 'approved-comm-' . uniqid(),
            'admin_id' => $owner->id,
            'submitted_by' => $owner->id,
            'city_id' => $city->id,
            'address' => 'Kalyani Nagar',
            'pincode' => '411006',
            'status' => 'pending_approval',
            'preferred_commercial_model' => 'commission',
            'requested_commission_percentage' => '18.00', // Requested by owner
        ]);

        // SuperAdmin approves with authoritative rate = 14.50%
        $response = $this->postJson("/api/superadmin/salons/{$salon->id}/approve", [
            'commercial_model' => 'commission',
            'commission_percentage' => 14.50,
        ]);
        $response->assertStatus(200)
            ->assertJsonPath('success', true);

        $salon->refresh();
        $this->assertEquals('active', $salon->status);
        $this->assertTrue((bool) $salon->commission_opt_in);
        $this->assertEquals('14.50', (string) $salon->commission_percentage);
        $this->assertEquals('18.00', (string) $salon->requested_commission_percentage); // Preserved intact!

        // Welcome bonus check
        $welcomeTxCount = WalletTransaction::where('salon_id', $salon->id)
            ->where('type', WalletTransaction::TYPE_WELCOME_BONUS)
            ->count();
        $this->assertEquals(1, $welcomeTxCount);

        // Approve again (idempotency check)
        $repeatResponse = $this->postJson("/api/superadmin/salons/{$salon->id}/approve", [
            'commercial_model' => 'commission',
            'commission_percentage' => 14.50,
        ]);
        $repeatResponse->assertStatus(200);

        // Verify bonus was NOT duplicated
        $repeatWelcomeTxCount = WalletTransaction::where('salon_id', $salon->id)
            ->where('type', WalletTransaction::TYPE_WELCOME_BONUS)
            ->count();
        $this->assertEquals(1, $repeatWelcomeTxCount);
    }

    public function test_superadmin_request_corrections_updates_status(): void
    {
        $city = City::first() ?? City::create(['name' => 'Pune', 'state' => 'Maharashtra', 'is_active' => true]);
        $owner = User::create([
            'name' => 'Correction Owner',
            'phone' => '92222' . rand(10000, 99999),
            'password_hash' => 'x',
            'role' => 'salon_owner',
            'is_active' => true,
        ]);

        $salon = Salon::create([
            'name' => 'Correction Salon ' . uniqid(),
            'slug' => 'corr-salon-' . uniqid(),
            'admin_id' => $owner->id,
            'submitted_by' => $owner->id,
            'city_id' => $city->id,
            'address' => 'Camp Area',
            'pincode' => '411001',
            'status' => 'pending_approval',
        ]);

        $response = $this->postJson("/api/superadmin/salons/{$salon->id}/request-corrections", [
            'correction_notes' => 'Please re-upload clearer facade photos and check your pincode.',
        ]);

        $response->assertStatus(200)
            ->assertJsonPath('success', true);

        $salon->refresh();
        $this->assertEquals('needs_correction', $salon->status);
        $this->assertEquals('Please re-upload clearer facade photos and check your pincode.', $salon->correction_notes);
        $this->assertNotNull($salon->correction_requested_at);
    }

    public function test_applicant_resubmission_updates_existing_salon_without_duplicates(): void
    {
        $city = City::first() ?? City::create(['name' => 'Pune', 'state' => 'Maharashtra', 'is_active' => true]);
        $subArea = SubArea::first() ?? SubArea::create(['city_id' => $city->id, 'name' => 'Camp']);
        $owner = User::create([
            'name' => 'Resubmit Owner',
            'phone' => '91111' . rand(10000, 99999),
            'email' => 'resubmit' . uniqid() . '@example.com',
            'password_hash' => 'x',
            'role' => 'salon_owner',
            'is_active' => true,
        ]);

        $salon = Salon::create([
            'name' => 'Original Salon Name',
            'slug' => 'original-salon-' . uniqid(),
            'admin_id' => $owner->id,
            'submitted_by' => $owner->id,
            'city_id' => $city->id,
            'sub_area_id' => $subArea->id,
            'address' => 'Old Address',
            'pincode' => '411001',
            'status' => 'needs_correction',
            'correction_notes' => 'Fix address',
            'cover_photo_url' => 'https://example.com/old_cover.jpg',
        ]);

        $totalSalonsBefore = Salon::count();

        // Resubmit with updated salon_id
        $photo = UploadedFile::fake()->create('new_front.jpg', 100, 'image/jpeg');
        $payload = [
            'salon_id' => $salon->id,
            'full_name' => 'Resubmit Owner',
            'email' => $owner->email,
            'phone_number' => $owner->phone,
            'password' => 'secret123',
            'salon_name' => 'Corrected Salon Name',
            'description' => 'Updated description',
            'street_address' => 'New Correct Address, Camp',
            'city_id' => $city->id,
            'sub_area_id' => $subArea->id,
            'pincode' => '411001',
            'gender_focus' => 'Unisex',
            'preferred_commercial_model' => 'subscription',
            'photos' => [$photo],
            'cover_index' => 0,
        ];

        $response = $this->actingAs($owner, 'sanctum')->post('/api/partner/register', $payload);
        $response->assertStatus(200);

        // Verify count didn't increase (no duplicate created!)
        $this->assertEquals($totalSalonsBefore, Salon::count());

        $salon->refresh();
        $this->assertEquals('pending_approval', $salon->status);
        $this->assertEquals('Corrected Salon Name', $salon->name);
        $this->assertNotNull($salon->resubmitted_at);
    }

    public function test_registration_approval_does_not_create_or_activate_subscription(): void
    {
        $city = City::first() ?? City::create(['name' => 'Pune', 'state' => 'Maharashtra', 'is_active' => true]);
        $owner = User::create([
            'name' => 'Sub Separation Owner',
            'phone' => '90000' . rand(10000, 99999),
            'password_hash' => 'x',
            'role' => 'salon_owner',
            'is_active' => true,
        ]);
        $plan = SubscriptionPlan::first() ?? SubscriptionPlan::create([
            'name' => 'Premium Plan',
            'price' => 2999,
            'duration_days' => 90,
            'is_active' => true,
        ]);

        $salon = Salon::create([
            'name' => 'Separation Test Salon ' . uniqid(),
            'slug' => 'sep-test-' . uniqid(),
            'admin_id' => $owner->id,
            'submitted_by' => $owner->id,
            'city_id' => $city->id,
            'address' => 'Aundh Road',
            'pincode' => '411007',
            'status' => 'pending_approval',
            'preferred_plan_id' => $plan->id,
            'preferred_commercial_model' => 'subscription',
        ]);

        // SuperAdmin approves registration
        $response = $this->postJson("/api/superadmin/salons/{$salon->id}/approve", [
            'commercial_model' => 'subscription',
        ]);
        $response->assertStatus(200);

        $salon->refresh();
        $this->assertEquals('active', $salon->status);

        // Crucial safety assertion: Stage A approval must NOT create a subscription!
        $subscriptionCount = SalonSubscription::where('salon_id', $salon->id)->count();
        $this->assertEquals(0, $subscriptionCount, 'Registration approval must NOT create an active subscription.');
    }
}
