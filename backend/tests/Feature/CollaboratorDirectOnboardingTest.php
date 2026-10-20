<?php

namespace Tests\Feature;

use App\Models\City;
use App\Models\Salon;
use App\Models\SalonEnquiry;
use App\Models\SubArea;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CollaboratorDirectOnboardingTest extends TestCase
{
    use RefreshDatabase;

    private User $collaborator;
    private User $otherCollaborator;
    private User $superAdmin;
    private City $city;
    private SubArea $subArea;

    protected function setUp(): void
    {
        parent::setUp();

        $this->city = City::create(['name' => 'Mumbai', 'state' => 'Maharashtra', 'is_active' => true]);
        $this->subArea = SubArea::create(['name' => 'Bandra', 'city_id' => $this->city->id, 'is_active' => true]);

        $this->collaborator = User::create([
            'role' => 'collaborator',
            'name' => 'Rahul Collaborator',
            'phone' => '9876500001',
            'password_hash' => bcrypt('password'),
        ]);

        $this->otherCollaborator = User::create([
            'role' => 'collaborator',
            'name' => 'Amit Collaborator',
            'phone' => '9876500002',
            'password_hash' => bcrypt('password'),
        ]);

        $this->superAdmin = User::create([
            'role' => 'superadmin',
            'name' => 'Super Admin',
            'phone' => '9999999999',
            'password_hash' => bcrypt('password'),
        ]);
    }

    private function validPayload(array $overrides = []): array
    {
        return array_merge([
            'salon_name' => 'Glow & Shine Direct',
            'description' => 'A wonderful direct onboarded salon.',
            'address' => '123 Linking Road',
            'city_id' => $this->city->id,
            'sub_area_id' => $this->subArea->id,
            'pincode' => '400050',
            'salon_phone' => '9876543210',
            'owner_name' => 'Ramesh Owner',
            'owner_phone' => '9123456780',
            'owner_email' => 'ramesh@example.com',
            'gender_focus' => 'Unisex',
            'working_hours' => json_encode([
                ['day_of_week' => 1, 'is_closed' => false, 'open_time' => '10:00', 'close_time' => '20:00'],
                ['day_of_week' => 2, 'is_closed' => false, 'open_time' => '10:00', 'close_time' => '20:00'],
            ]),
            'photos' => [
                UploadedFile::fake()->create('cover.jpg', 100, 'image/jpeg'),
            ],
            'cover_index' => 0,
        ], $overrides);
    }

    public function test_collaborator_can_onboard_salon_directly_without_enquiry_or_services(): void
    {
        Sanctum::actingAs($this->collaborator);

        $payload = $this->validPayload();
        $response = $this->post('/api/partner/collaborator/onboard', $payload);

        $response->assertStatus(201);
        $response->assertJsonPath('success', true);
        $response->assertJsonPath('data.name', 'Glow & Shine Direct');

        $salon = Salon::where('name', 'Glow & Shine Direct')->first();
        $this->assertNotNull($salon);
        $this->assertNull($salon->enquiry_id);
        $this->assertEquals($this->collaborator->id, $salon->submitted_by);
        $this->assertEquals('pending_approval', $salon->status);
        $this->assertEquals(0, $salon->services()->count());
    }

    public function test_submitted_salon_appears_in_my_salons_and_superadmin_approval_queue(): void
    {
        Sanctum::actingAs($this->collaborator);
        $this->post('/api/partner/collaborator/onboard', $this->validPayload())->assertStatus(201);

        // Collaborator's My Salons endpoint
        $mySalonsRes = $this->getJson('/api/partner/collaborator/onboarded-salons');
        $mySalonsRes->assertStatus(200);
        $mySalonsRes->assertJsonPath('success', true);
        $this->assertCount(1, $mySalonsRes->json('data'));
        $this->assertEquals('Glow & Shine Direct', $mySalonsRes->json('data.0.name'));
        $this->assertEquals('pending_approval', $mySalonsRes->json('data.0.status'));
        $this->assertTrue($mySalonsRes->json('data.0.can_edit'));

        // Collaborator's Home dashboard counts
        $profileRes = $this->getJson('/api/partner/collaborator/me');
        $profileRes->assertStatus(200);
        $this->assertEquals(1, $profileRes->json('data.stats.pending'));
        $this->assertEquals(0, $profileRes->json('data.stats.approved'));
        $this->assertEquals(0, $profileRes->json('data.stats.rejected'));

        // SuperAdmin approval queue
        Sanctum::actingAs($this->superAdmin);
        $adminRes = $this->getJson('/api/superadmin/salons/pending');
        $adminRes->assertStatus(200);
        $this->assertCount(1, $adminRes->json('data'));
        $this->assertEquals('Glow & Shine Direct', $adminRes->json('data.0.name'));
    }

    public function test_approved_salon_becomes_read_only_and_api_modification_is_rejected_with_403(): void
    {
        Sanctum::actingAs($this->collaborator);
        $this->post('/api/partner/collaborator/onboard', $this->validPayload())->assertStatus(201);
        $salon = Salon::where('name', 'Glow & Shine Direct')->firstOrFail();

        // SuperAdmin approves
        Sanctum::actingAs($this->superAdmin);
        $approveRes = $this->postJson("/api/superadmin/salons/{$salon->id}/approve");
        $approveRes->assertStatus(200);
        $this->assertEquals('active', $salon->fresh()->status);

        // Check My Salons: can_edit is false
        Sanctum::actingAs($this->collaborator);
        $mySalonsRes = $this->getJson('/api/partner/collaborator/onboarded-salons');
        $this->assertFalse($mySalonsRes->json('data.0.can_edit'));

        // Collaborator tries to modify approved salon via direct API
        $editPayload = $this->validPayload([
            'salon_id' => $salon->id,
            'salon_name' => 'Hacked Salon Name',
        ]);
        $editRes = $this->post('/api/partner/collaborator/onboard', $editPayload);
        $editRes->assertStatus(403);
        $editRes->assertJsonPath('success', false);

        // Ensure name was unchanged
        $this->assertEquals('Glow & Shine Direct', $salon->fresh()->name);
    }

    public function test_rejected_salon_displays_rejection_reason_and_updates_dashboard_counts(): void
    {
        Sanctum::actingAs($this->collaborator);
        $this->post('/api/partner/collaborator/onboard', $this->validPayload())->assertStatus(201);
        $salon = Salon::where('name', 'Glow & Shine Direct')->firstOrFail();

        // SuperAdmin rejects
        Sanctum::actingAs($this->superAdmin);
        $rejectRes = $this->postJson("/api/superadmin/salons/{$salon->id}/reject", [
            'rejection_reason' => 'Address proof unclear, please upload shop act.',
        ]);
        $rejectRes->assertStatus(200);

        // Collaborator My Salons
        Sanctum::actingAs($this->collaborator);
        $mySalonsRes = $this->getJson('/api/partner/collaborator/onboarded-salons');
        $this->assertEquals('rejected', $mySalonsRes->json('data.0.status'));
        $this->assertEquals('Address proof unclear, please upload shop act.', $mySalonsRes->json('data.0.rejection_reason'));
        $this->assertTrue($mySalonsRes->json('data.0.can_edit'));

        // Dashboard stats reflect rejected count
        $profileRes = $this->getJson('/api/partner/collaborator/me');
        $this->assertEquals(0, $profileRes->json('data.stats.pending'));
        $this->assertEquals(1, $profileRes->json('data.stats.rejected'));
    }

    public function test_assigned_tab_does_not_contain_direct_onboarded_salons(): void
    {
        Sanctum::actingAs($this->collaborator);
        $this->post('/api/partner/collaborator/onboard', $this->validPayload())->assertStatus(201);

        // Assigned salons query
        $assignedRes = $this->getJson('/api/partner/collaborator/assigned-salons');
        $assignedRes->assertStatus(200);
        $this->assertCount(0, $assignedRes->json('data'));

        // Now create a ready-made directory salon assigned to collaborator by SuperAdmin
        $adminUser = User::create([
            'role' => 'admin',
            'name' => 'Directory Admin',
            'phone' => '9988776655',
            'password_hash' => bcrypt('password'),
        ]);

        $assignedSalon = Salon::create([
            'admin_id' => $adminUser->id,
            'name' => 'Assigned Ready Salon',
            'slug' => 'assigned-ready-salon',
            'address' => '456 Hill Road',
            'city_id' => $this->city->id,
            'sub_area_id' => $this->subArea->id,
            'status' => 'active',
            'submitted_by' => $adminUser->id, // Not submitted by this collaborator
            'assigned_collaborator_id' => $this->collaborator->id,
            'enquiry_id' => null,
        ]);

        $assignedRes2 = $this->getJson('/api/partner/collaborator/assigned-salons');
        $assignedRes2->assertStatus(200);
        $this->assertCount(1, $assignedRes2->json('data'));
        $this->assertEquals('Assigned Ready Salon', $assignedRes2->json('data.0.name'));
    }

    public function test_collaborator_cannot_view_or_edit_another_collaborators_salons(): void
    {
        Sanctum::actingAs($this->collaborator);
        $this->post('/api/partner/collaborator/onboard', $this->validPayload())->assertStatus(201);
        $salon = Salon::where('name', 'Glow & Shine Direct')->firstOrFail();

        // Other collaborator attempts to fetch submitted salon details
        Sanctum::actingAs($this->otherCollaborator);
        $viewRes = $this->getJson("/api/partner/collaborator/salons/{$salon->id}/submission");
        $viewRes->assertStatus(403);
        $viewRes->assertJsonPath('success', false);

        // Other collaborator attempts to modify via onboardDirect
        $hackPayload = $this->validPayload([
            'salon_id' => $salon->id,
            'salon_name' => 'Stolen Salon',
        ]);
        $hackRes = $this->post('/api/partner/collaborator/onboard', $hackPayload);
        $hackRes->assertStatus(403);
        $hackRes->assertJsonPath('success', false);
    }

<<<<<<< HEAD
    public function test_uploading_multiple_photos_selects_correct_cover_and_does_not_duplicate_salon(): void
    {
        Sanctum::actingAs($this->collaborator);

        $photo1 = UploadedFile::fake()->create('facade1.jpg', 150, 'image/jpeg');
        $photo2 = UploadedFile::fake()->create('interior_cover.jpg', 200, 'image/jpeg');

        // First onboarding submission with 2 photos, choosing photo 2 (index 1) as cover photo
        $payload1 = $this->validPayload([
            'salon_name' => 'Mirror & Mane Studio',
            'owner_phone' => '9888877777',
            'photos' => [$photo1, $photo2],
            'cover_index' => 1,
        ]);

        $res1 = $this->post('/api/partner/collaborator/onboard', $payload1);
        $res1->assertStatus(201);
        $res1->assertJsonPath('success', true);

        $salon = Salon::where('name', 'Mirror & Mane Studio')->first();
        $this->assertNotNull($salon);
        $this->assertEquals(1, Salon::where('name', 'Mirror & Mane Studio')->count());
        $this->assertEquals(2, $salon->media()->count());

        // The second photo must be the designated cover photo
        $coverMedia = $salon->media()->where('is_cover', true)->first();
        $this->assertNotNull($coverMedia);
        $this->assertEquals(1, $coverMedia->sort_order);
        $this->assertEquals($salon->cover_photo_url, $coverMedia->file_url);

        // Simulate subsequent submission (e.g. background sync or re-submit when photos added)
        $photo3 = UploadedFile::fake()->create('updated_cover.jpg', 250, 'image/jpeg');
        $payload2 = $this->validPayload([
            'salon_name' => 'Mirror & Mane Studio',
            'owner_phone' => '9888877777',
            'photos' => [$photo1, $photo3],
            'cover_index' => 1,
        ]);

        $res2 = $this->post('/api/partner/collaborator/onboard', $payload2);
        $res2->assertStatus(200);

        // Verification: Still ONLY ONE salon exists in the database
        $this->assertEquals(1, Salon::where('name', 'Mirror & Mane Studio')->count());
=======
    public function test_collaborator_can_onboard_salon_without_reception_phone_number(): void
    {
        Sanctum::actingAs($this->collaborator);
        $payload = $this->validPayload([
            'salon_name' => 'Receptionless Salon',
            'salon_phone' => null,
        ]);
        unset($payload['salon_phone']);

        $res = $this->post('/api/partner/collaborator/onboard', $payload);
        $res->assertStatus(201);

        $salon = Salon::where('name', 'Receptionless Salon')->firstOrFail();
        $this->assertNull($salon->phone_num);
>>>>>>> c648da65372b1a05f820bd7b69851052e98dac6f
    }
}
