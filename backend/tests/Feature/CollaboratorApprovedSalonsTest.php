<?php

namespace Tests\Feature;

use App\Models\City;
use App\Models\Salon;
use App\Models\SalonEnquiry;
use App\Models\SalonSubscription;
use App\Models\SubscriptionPlan;
use App\Models\SubArea;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CollaboratorApprovedSalonsTest extends TestCase
{
    use RefreshDatabase;

    private User $collaborator1;
    private User $collaborator2;
    private User $customer;
    private City $city;
    private SubArea $subArea;

    protected function setUp(): void
    {
        parent::setUp();

        $this->city = City::create(['name' => 'Mumbai', 'state' => 'Maharashtra', 'is_active' => true]);
        $this->subArea = SubArea::create(['name' => 'Bandra', 'city_id' => $this->city->id, 'is_active' => true]);

        $this->collaborator1 = User::create([
            'role' => 'collaborator',
            'name' => 'Collaborator One',
            'phone' => '9876500001',
            'password_hash' => bcrypt('password'),
        ]);

        $this->collaborator2 = User::create([
            'role' => 'collaborator',
            'name' => 'Collaborator Two',
            'phone' => '9876500002',
            'password_hash' => bcrypt('password'),
        ]);

        $this->customer = User::create([
            'role' => 'customer',
            'name' => 'Customer User',
            'phone' => '9876500003',
            'password_hash' => bcrypt('password'),
        ]);
    }

    private function createSalon(array $attributes = []): Salon
    {
        $admin = User::create([
            'role' => 'admin',
            'name' => 'Owner ' . uniqid(),
            'phone' => '98' . rand(10000000, 99999999),
            'password_hash' => bcrypt('password'),
        ]);

        return Salon::create(array_merge([
            'name' => 'Test Salon ' . uniqid(),
            'slug' => 'test-salon-' . uniqid(),
            'admin_id' => $admin->id,
            'address' => '123 Main Road',
            'city_id' => $this->city->id,
            'sub_area_id' => $this->subArea->id,
            'phone_num' => '9876543210',
            'gender_focus' => 'Unisex',
            'status' => 'pending_approval',
            'submitted_by' => $this->collaborator1->id,
        ], $attributes));
    }

    public function test_approved_salons_requires_authentication(): void
    {
        $response = $this->getJson('/api/partner/collaborator/approved-salons');
        $response->assertStatus(401);
    }

    public function test_approved_salons_forbids_non_collaborators(): void
    {
        Sanctum::actingAs($this->customer);

        $response = $this->getJson('/api/partner/collaborator/approved-salons');
        $response->assertStatus(403)
            ->assertJson(['success' => false]);
    }

    public function test_approved_salons_returns_empty_array_when_collaborator_has_no_salons(): void
    {
        Sanctum::actingAs($this->collaborator1);

        $response = $this->getJson('/api/partner/collaborator/approved-salons');
        $response->assertStatus(200)
            ->assertJson([
                'success' => true,
                'data' => [],
            ]);
    }

    public function test_approved_salons_only_returns_explicitly_approved_salons_for_authenticated_collaborator(): void
    {
        // Collaborator 1 salons:
        // 1. Approved salon (status = 'active', approved_at set)
        $approvedSalon = $this->createSalon([
            'name' => 'Collab1 Approved Salon',
            'submitted_by' => $this->collaborator1->id,
            'status' => 'active',
            'approved_at' => now(),
        ]);

        // 2. Pending salon (status = 'pending_approval')
        $pendingSalon = $this->createSalon([
            'name' => 'Collab1 Pending Salon',
            'submitted_by' => $this->collaborator1->id,
            'status' => 'pending_approval',
            'approved_at' => null,
        ]);

        // 3. Rejected salon (status = 'rejected')
        $rejectedSalon = $this->createSalon([
            'name' => 'Collab1 Rejected Salon',
            'submitted_by' => $this->collaborator1->id,
            'status' => 'rejected',
            'rejection_reason' => 'Incomplete documents',
        ]);

        // 4. Needs correction salon
        $needsCorrectionSalon = $this->createSalon([
            'name' => 'Collab1 Needs Correction Salon',
            'submitted_by' => $this->collaborator1->id,
            'status' => 'needs_correction',
            'correction_notes' => 'Please update photos',
        ]);

        // Collaborator 2 salon (approved):
        $collab2ApprovedSalon = $this->createSalon([
            'name' => 'Collab2 Approved Salon',
            'submitted_by' => $this->collaborator2->id,
            'status' => 'active',
            'approved_at' => now(),
        ]);

        Sanctum::actingAs($this->collaborator1);

        $response = $this->getJson('/api/partner/collaborator/approved-salons');
        $response->assertStatus(200)
            ->assertJson(['success' => true]);

        $data = $response->json('data');
        $this->assertCount(1, $data);
        $this->assertEquals($approvedSalon->id, $data[0]['id']);
        $this->assertEquals('Collab1 Approved Salon', $data[0]['name']);
        $this->assertTrue($data[0]['is_approved']);

        // Assert strictly excludes pending, rejected, needs correction, and other collaborator's salons
        $returnedIds = collect($data)->pluck('id')->all();
        $this->assertNotContains($pendingSalon->id, $returnedIds);
        $this->assertNotContains($rejectedSalon->id, $returnedIds);
        $this->assertNotContains($needsCorrectionSalon->id, $returnedIds);
        $this->assertNotContains($collab2ApprovedSalon->id, $returnedIds);
    }

    public function test_approved_salons_includes_assigned_collaborator_and_enquiry_assignments(): void
    {
        // Salon assigned directly via assigned_collaborator_id
        $assignedSalon = $this->createSalon([
            'name' => 'Assigned Active Salon',
            'submitted_by' => $this->collaborator2->id,
            'assigned_collaborator_id' => $this->collaborator1->id,
            'status' => 'active',
            'approved_at' => now(),
        ]);

        // Salon assigned via enquiry
        $enquiry = SalonEnquiry::create([
            'salon_name' => 'Enquiry Salon',
            'owner_name' => 'Owner',
            'phone' => '9998887776',
            'city_id' => $this->city->id,
            'assigned_collaborator_id' => $this->collaborator1->id,
            'status' => 'assigned',
        ]);

        $enquirySalon = $this->createSalon([
            'name' => 'Enquiry Active Salon',
            'submitted_by' => $this->collaborator2->id,
            'enquiry_id' => $enquiry->id,
            'status' => 'approved',
            'approved_at' => now(),
        ]);

        Sanctum::actingAs($this->collaborator1);

        $response = $this->getJson('/api/partner/collaborator/approved-salons');
        $response->assertStatus(200);

        $returnedIds = collect($response->json('data'))->pluck('id')->all();
        $this->assertContains($assignedSalon->id, $returnedIds);
        $this->assertContains($enquirySalon->id, $returnedIds);
    }

    public function test_onboarded_salons_returns_all_statuses_with_correct_status_and_is_approved_flag(): void
    {
        $approvedSalon = $this->createSalon([
            'name' => 'Collab1 Approved Salon',
            'submitted_by' => $this->collaborator1->id,
            'status' => 'active',
            'approved_at' => now(),
        ]);

        $pendingSalon = $this->createSalon([
            'name' => 'Collab1 Pending Salon',
            'submitted_by' => $this->collaborator1->id,
            'status' => 'pending_approval',
        ]);

        $rejectedSalon = $this->createSalon([
            'name' => 'Collab1 Rejected Salon',
            'submitted_by' => $this->collaborator1->id,
            'status' => 'rejected',
            'correction_notes' => 'Please provide valid license',
        ]);

        Sanctum::actingAs($this->collaborator1);

        $response = $this->getJson('/api/partner/collaborator/onboarded-salons');
        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertCount(3, $data);

        $byId = collect($data)->keyBy('id');

        $this->assertEquals('active', $byId[$approvedSalon->id]['status']);
        $this->assertTrue($byId[$approvedSalon->id]['is_approved']);

        $this->assertEquals('pending_approval', $byId[$pendingSalon->id]['status']);
        $this->assertFalse($byId[$pendingSalon->id]['is_approved']);

        $this->assertEquals('rejected', $byId[$rejectedSalon->id]['status']);
        $this->assertFalse($byId[$rejectedSalon->id]['is_approved']);
        $this->assertEquals('Please provide valid license', $byId[$rejectedSalon->id]['rejection_reason']);
    }

    public function test_onboarded_salons_status_filter_parameter(): void
    {
        $approvedSalon = $this->createSalon([
            'name' => 'Collab1 Approved Salon',
            'submitted_by' => $this->collaborator1->id,
            'status' => 'active',
            'approved_at' => now(),
        ]);

        $pendingSalon = $this->createSalon([
            'name' => 'Collab1 Pending Salon',
            'submitted_by' => $this->collaborator1->id,
            'status' => 'pending_approval',
        ]);

        Sanctum::actingAs($this->collaborator1);

        // Filter approved
        $resApproved = $this->getJson('/api/partner/collaborator/onboarded-salons?status=approved');
        $resApproved->assertStatus(200);
        $idsApproved = collect($resApproved->json('data'))->pluck('id')->all();
        $this->assertContains($approvedSalon->id, $idsApproved);
        $this->assertNotContains($pendingSalon->id, $idsApproved);

        // Filter pending
        $resPending = $this->getJson('/api/partner/collaborator/onboarded-salons?status=pending');
        $resPending->assertStatus(200);
        $idsPending = collect($resPending->json('data'))->pluck('id')->all();
        $this->assertContains($pendingSalon->id, $idsPending);
        $this->assertNotContains($approvedSalon->id, $idsPending);
    }

    public function test_assigned_enquiries_returns_enquiries_with_city_and_correction_notes(): void
    {
        $enquiry = SalonEnquiry::create([
            'salon_name' => 'Assigned Enquiry Salon',
            'owner_name' => 'Rohan Joshi',
            'phone' => '9820011223',
            'city_id' => $this->city->id,
            'status' => 'assigned',
            'assigned_collaborator_id' => $this->collaborator1->id,
            'assigned_at' => now(),
            'message' => 'New onboarding request',
        ]);

        Sanctum::actingAs($this->collaborator1);

        $res = $this->getJson('/api/partner/collaborator/assigned-enquiries');
        $res->assertStatus(200)
            ->assertJson(['success' => true]);

        $data = $res->json('data');
        $this->assertCount(1, $data);
        $this->assertEquals($enquiry->id, $data[0]['id']);
        $this->assertEquals('Assigned Enquiry Salon', $data[0]['salon_name']);
        $this->assertEquals('Mumbai', $data[0]['city']);
        $this->assertFalse($data[0]['needs_correction']);

        // Data isolation: collaborator 2 cannot see collaborator 1's enquiries
        Sanctum::actingAs($this->collaborator2);
        $res2 = $this->getJson('/api/partner/collaborator/assigned-enquiries');
        $res2->assertStatus(200)
            ->assertJson(['success' => true, 'data' => []]);
    }

    public function test_assigned_salons_returns_assigned_salons_and_isolates_collaborators(): void
    {
        $assignedSalon = $this->createSalon([
            'name' => 'Handed Over Salon',
            'assigned_collaborator_id' => $this->collaborator1->id,
            'submitted_by' => $this->collaborator2->id,
            'status' => 'active',
            'approved_at' => now(),
        ]);

        Sanctum::actingAs($this->collaborator1);

        $res = $this->getJson('/api/partner/collaborator/assigned-salons');
        $res->assertStatus(200)
            ->assertJson(['success' => true]);

        $ids = collect($res->json('data'))->pluck('id')->all();
        $this->assertContains($assignedSalon->id, $ids);
        $this->assertEquals('Mumbai', $res->json('data.0.city'));

        // Data isolation: collaborator 2 cannot see collaborator 1's assigned salons
        Sanctum::actingAs($this->collaborator2);
        $res2 = $this->getJson('/api/partner/collaborator/assigned-salons');
        $res2->assertStatus(200)
            ->assertJson(['success' => true, 'data' => []]);
    }

    public function test_onboarded_and_approved_salons_load_latest_subscription_safely(): void
    {
        $plan = SubscriptionPlan::create([
            'name' => 'Pro Plan',
            'price' => 1999,
            'duration_days' => 30,
            'is_active' => true,
        ]);

        $salon = $this->createSalon([
            'name' => 'Subscription Test Salon',
            'submitted_by' => $this->collaborator1->id,
            'status' => 'active',
            'approved_at' => now(),
        ]);

        // Prior expired subscription
        SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'start_date' => now()->subMonths(2),
            'end_date' => now()->subMonth(),
            'status' => 'expired',
        ]);

        // Current active subscription
        SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'start_date' => now()->subDays(5),
            'end_date' => now()->addDays(25),
            'status' => 'active',
        ]);

        Sanctum::actingAs($this->collaborator1);

        $onboardedRes = $this->getJson('/api/partner/collaborator/onboarded-salons');
        $onboardedRes->assertStatus(200)
            ->assertJson(['success' => true]);

        $approvedRes = $this->getJson('/api/partner/collaborator/approved-salons');
        $approvedRes->assertStatus(200)
            ->assertJson(['success' => true]);

        $this->assertEquals('Pro Plan', $approvedRes->json('data.0.plan_name'));
        $this->assertFalse($approvedRes->json('data.0.lapsed'));
        $this->assertFalse($approvedRes->json('data.0.needs_plan'));
        $this->assertNotNull($approvedRes->json('data.0.days_left'));
    }
}

