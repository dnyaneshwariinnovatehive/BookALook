<?php

namespace Tests\Feature;

use App\Models\City;
use App\Models\Salon;
use App\Models\SalonEnquiry;
use App\Models\SalonMedia;
use App\Models\SalonWorkingHour;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceTemplate;
use App\Models\SubArea;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CollaboratorServiceOnboardingTest extends TestCase
{
    use DatabaseTransactions;

    private City $city;
    private SubArea $subArea;
    private User $collaborator;
    private SalonEnquiry $enquiry;
    private ServiceCategory $standardCategory;
    private ServiceCategory $otherStandardCategory;
    private ServiceTemplate $templateA;
    private ServiceTemplate $templateB;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');

        $this->city = City::first() ?? City::create(['name' => 'Pune', 'state' => 'Maharashtra', 'is_active' => true]);
        $this->subArea = SubArea::where('city_id', $this->city->id)->first()
            ?? SubArea::create(['city_id' => $this->city->id, 'name' => 'Baner Locality ' . uniqid()]);

        $this->collaborator = User::create([
            'name' => 'Collaborator ' . uniqid(),
            'phone' => '9' . rand(100000000, 999999999),
            'role' => 'collaborator',
            'password_hash' => Hash::make('secret'),
            'is_active' => true,
        ]);

        $this->enquiry = SalonEnquiry::create([
            'salon_name' => 'Test Salon ' . uniqid(),
            'owner_name' => 'Owner ' . uniqid(),
            'phone' => '9' . rand(100000000, 999999999),
            'city_id' => $this->city->id,
            'assigned_collaborator_id' => $this->collaborator->id,
            'assigned_at' => now(),
            'status' => 'assigned',
        ]);

        $this->standardCategory = ServiceCategory::create([
            'name' => 'Hair Styling ' . uniqid(),
            'is_custom' => false,
            'is_active' => true,
        ]);

        $this->otherStandardCategory = ServiceCategory::create([
            'name' => 'Facial Care ' . uniqid(),
            'is_custom' => false,
            'is_active' => true,
        ]);

        $this->templateA = ServiceTemplate::create([
            'category_id' => $this->standardCategory->id,
            'name' => 'Standard Cut ' . uniqid(),
            'estimated_duration_minutes' => 30,
            'is_custom' => false,
            'is_active' => true,
        ]);

        $this->templateB = ServiceTemplate::create([
            'category_id' => $this->standardCategory->id,
            'name' => 'Standard Color ' . uniqid(),
            'estimated_duration_minutes' => 60,
            'is_custom' => false,
            'is_active' => true,
        ]);
    }

    private function basePayload(array $overrides = []): array
    {
        $photo = UploadedFile::fake()->create('cover.jpg', 100, 'image/jpeg');

        return array_merge([
            'owner_name' => 'Ram Kumar',
            'owner_phone' => '9876543210',
            'salon_name' => 'Ram Deluxe Salon',
            'description' => 'Premium salon and spa services',
            'address' => 'Plot 45, Main Road',
            'city_id' => $this->city->id,
            'sub_area_id' => $this->subArea->id,
            'pincode' => '411045',
            'salon_phone' => '02012345678',
            'gender_focus' => 'Unisex',
            'working_hours' => json_encode([
                ['day_of_week' => 1, 'is_closed' => false, 'open_time' => '10:00', 'close_time' => '20:00'],
                ['day_of_week' => 2, 'is_closed' => false, 'open_time' => '10:00', 'close_time' => '20:00'],
            ]),
            'photos' => [$photo],
            'cover_index' => 0,
        ], $overrides);
    }

    private function submitOnboard(string $enquiryId, array $payload)
    {
        return $this->withHeaders(['Accept' => 'application/json'])
            ->post("/api/partner/collaborator/enquiries/{$enquiryId}/onboard", $payload);
    }

    /** 1 & 2: A collaborator cannot submit the same standard template_id twice and gets a 422 */
    public function test_collaborator_cannot_submit_duplicate_standard_template_id(): void
    {
        Sanctum::actingAs($this->collaborator);

        $payload = $this->basePayload([
            'services' => json_encode([
                ['template_id' => $this->templateA->id, 'price' => 350],
                ['template_id' => $this->templateA->id, 'price' => 400], // Duplicate!
            ]),
        ]);

        $response = $this->submitOnboard($this->enquiry->id, $payload);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['services.1.template_id']);
    }

    /** 3: Duplicate custom service identities in one payload are rejected with 422 */
    public function test_duplicate_custom_service_identities_in_one_payload_are_rejected(): void
    {
        Sanctum::actingAs($this->collaborator);

        $payload = $this->basePayload([
            'services' => json_encode([
                [
                    'custom_template_name' => 'Signature Beard Trim',
                    'category_id' => $this->standardCategory->id,
                    'estimated_duration_minutes' => 30,
                    'price' => 250,
                ],
                [
                    'custom_template_name' => '  signature BEARD trim  ', // Case and whitespace variant in same category
                    'category_id' => $this->standardCategory->id,
                    'estimated_duration_minutes' => 30,
                    'price' => 300,
                ],
            ]),
        ]);

        $response = $this->submitOnboard($this->enquiry->id, $payload);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['services.1.custom_template_name']);
    }

    /** 4 & 5: Repeated submission of the same custom service reuses its custom template without duplicating services */
    public function test_repeated_submission_reuses_custom_template_and_does_not_duplicate_services(): void
    {
        Sanctum::actingAs($this->collaborator);

        $customName = 'Signature Head Massage ' . uniqid();

        // 1st submission
        $payload1 = $this->basePayload([
            'services' => json_encode([
                [
                    'custom_template_name' => $customName,
                    'custom_category_name' => 'Relaxation Spa',
                    'estimated_duration_minutes' => 45,
                    'price' => 500,
                ],
            ]),
        ]);

        $res1 = $this->submitOnboard($this->enquiry->id, $payload1);
        $res1->assertStatus(201);

        $salon = Salon::where('enquiry_id', $this->enquiry->id)->firstOrFail();
        $templatesBefore = ServiceTemplate::where('created_by_salon_id', $salon->id)->get();
        $this->assertCount(1, $templatesBefore);
        $firstTemplateId = $templatesBefore->first()->id;

        $servicesBefore = Service::where('salon_id', $salon->id)->get();
        $this->assertCount(1, $servicesBefore);
        $this->assertEquals(500.0, (float) $servicesBefore->first()->price);

        // 2nd submission (resubmission/retry with same custom service at updated price)
        $payload2 = $this->basePayload([
            'services' => json_encode([
                [
                    'custom_template_name' => strtolower($customName),
                    'custom_category_name' => 'Relaxation Spa',
                    'estimated_duration_minutes' => 45,
                    'price' => 550,
                ],
            ]),
        ]);

        $res2 = $this->submitOnboard($this->enquiry->id, $payload2);
        $res2->assertStatus(200);

        // Verify custom template was REUSED rather than duplicated
        $templatesAfter = ServiceTemplate::where('created_by_salon_id', $salon->id)->get();
        $this->assertCount(1, $templatesAfter);
        $this->assertEquals($firstTemplateId, $templatesAfter->first()->id);

        // Verify service offering count is still 1, and price updated
        $servicesAfter = Service::where('salon_id', $salon->id)->get();
        $this->assertCount(1, $servicesAfter);
        $this->assertEquals(550.0, (float) $servicesAfter->first()->price);
    }

    /** 6: Editing a draft and removing a service reconciles the persisted list correctly */
    public function test_editing_draft_and_removing_service_reconciles_active_services(): void
    {
        Sanctum::actingAs($this->collaborator);

        // Initial submission with 2 services (templateA and templateB)
        $payload1 = $this->basePayload([
            'services' => json_encode([
                ['template_id' => $this->templateA->id, 'price' => 300],
                ['template_id' => $this->templateB->id, 'price' => 600],
            ]),
        ]);

        $res1 = $this->submitOnboard($this->enquiry->id, $payload1);
        $res1->assertStatus(201);

        $salon = Salon::where('enquiry_id', $this->enquiry->id)->firstOrFail();
        $this->assertEquals(2, Service::where('salon_id', $salon->id)->count());

        // Resubmission removing templateB (keeping only templateA)
        $payload2 = $this->basePayload([
            'services' => json_encode([
                ['template_id' => $this->templateA->id, 'price' => 320],
            ]),
        ]);

        $res2 = $this->submitOnboard($this->enquiry->id, $payload2);
        $res2->assertStatus(200);

        // Active services must only be 1 (templateA)
        $activeServices = Service::where('salon_id', $salon->id)->get();
        $this->assertCount(1, $activeServices);
        $this->assertEquals($this->templateA->id, $activeServices->first()->template_id);
        $this->assertEquals(320.0, (float) $activeServices->first()->price);

        // templateB must be soft-deleted
        $trashedB = Service::onlyTrashed()->where('salon_id', $salon->id)->where('template_id', $this->templateB->id)->first();
        $this->assertNotNull($trashedB);
    }

    /** 7: An omitted services field does not accidentally delete existing services */
    public function test_omitted_services_field_does_not_delete_existing_services(): void
    {
        Sanctum::actingAs($this->collaborator);

        // Initial submission with 1 service
        $payload1 = $this->basePayload([
            'services' => json_encode([
                ['template_id' => $this->templateA->id, 'price' => 300],
            ]),
        ]);

        $res1 = $this->submitOnboard($this->enquiry->id, $payload1);
        $res1->assertStatus(201);

        $salon = Salon::where('enquiry_id', $this->enquiry->id)->firstOrFail();
        $this->assertEquals(1, Service::where('salon_id', $salon->id)->count());

        // Resubmission WITHOUT the 'services' key in payload (omitted)
        $payload2 = $this->basePayload();
        unset($payload2['services']);

        $res2 = $this->submitOnboard($this->enquiry->id, $payload2);
        $res2->assertStatus(200);

        // Service must still exist and be active!
        $this->assertEquals(1, Service::where('salon_id', $salon->id)->count());
    }

    /** 8: An explicitly empty list follows the intended business rule (reconciles down to 0) */
    public function test_explicitly_empty_services_list_reconciles_active_services(): void
    {
        Sanctum::actingAs($this->collaborator);

        $payload1 = $this->basePayload([
            'services' => json_encode([
                ['template_id' => $this->templateA->id, 'price' => 300],
            ]),
        ]);

        $res1 = $this->submitOnboard($this->enquiry->id, $payload1);
        $res1->assertStatus(201);

        $salon = Salon::where('enquiry_id', $this->enquiry->id)->firstOrFail();
        $this->assertEquals(1, Service::where('salon_id', $salon->id)->count());

        // Resubmission with explicitly empty array
        $payload2 = $this->basePayload([
            'services' => json_encode([]),
        ]);

        $res2 = $this->submitOnboard($this->enquiry->id, $payload2);
        $res2->assertStatus(200);

        $this->assertEquals(0, Service::where('salon_id', $salon->id)->count());
        $this->assertEquals(1, Service::onlyTrashed()->where('salon_id', $salon->id)->count());
    }

    /** 9: A matching soft-deleted service is restored safely without unique-key exception */
    public function test_matching_soft_deleted_service_is_restored_safely(): void
    {
        Sanctum::actingAs($this->collaborator);

        // 1. Add templateA
        $payload1 = $this->basePayload([
            'services' => json_encode([
                ['template_id' => $this->templateA->id, 'price' => 300],
            ]),
        ]);
        $this->submitOnboard($this->enquiry->id, $payload1)->assertStatus(201);
        $salon = Salon::where('enquiry_id', $this->enquiry->id)->firstOrFail();

        // 2. Remove templateA by submitting templateB
        $payload2 = $this->basePayload([
            'services' => json_encode([
                ['template_id' => $this->templateB->id, 'price' => 500],
            ]),
        ]);
        $this->submitOnboard($this->enquiry->id, $payload2)->assertStatus(200);

        $this->assertTrue(Service::onlyTrashed()->where('salon_id', $salon->id)->where('template_id', $this->templateA->id)->exists());

        // 3. Re-add templateA at updated price 350
        $payload3 = $this->basePayload([
            'services' => json_encode([
                ['template_id' => $this->templateA->id, 'price' => 350],
                ['template_id' => $this->templateB->id, 'price' => 500],
            ]),
        ]);
        $res3 = $this->submitOnboard($this->enquiry->id, $payload3);
        $res3->assertStatus(200);

        // Verify templateA is restored (not trashed) and has updated price
        $restoredA = Service::where('salon_id', $salon->id)->where('template_id', $this->templateA->id)->firstOrFail();
        $this->assertNull($restoredA->deleted_at);
        $this->assertEquals(350.0, (float) $restoredA->price);
        $this->assertEquals(2, Service::where('salon_id', $salon->id)->count());
    }

    /** 10: Custom templates belonging to another salon are never reused */
    public function test_custom_templates_belonging_to_another_salon_are_never_reused(): void
    {
        Sanctum::actingAs($this->collaborator);

        // Other salon
        $otherOwner = User::create([
            'name' => 'Other Owner',
            'phone' => '9' . rand(100000000, 999999999),
            'role' => 'salon_owner',
            'password_hash' => 'x',
            'is_active' => true,
        ]);
        $otherSalon = Salon::create([
            'name' => 'Other Salon',
            'slug' => 'other-salon-' . uniqid(),
            'admin_id' => $otherOwner->id,
            'submitted_by' => $this->collaborator->id,
            'city_id' => $this->city->id,
            'sub_area_id' => $this->subArea->id,
            'address' => 'Other Address',
            'pincode' => '411045',
            'status' => 'pending_approval',
        ]);

        $foreignCustomTemplate = ServiceTemplate::create([
            'category_id' => $this->standardCategory->id,
            'name' => 'Foreign Exclusive Spa',
            'estimated_duration_minutes' => 60,
            'is_custom' => true,
            'created_by_salon_id' => $otherSalon->id,
            'is_active' => true,
        ]);

        // Collaborator submits a custom service with the exact same name for this salon
        $payload = $this->basePayload([
            'services' => json_encode([
                [
                    'custom_template_name' => 'Foreign Exclusive Spa',
                    'category_id' => $this->standardCategory->id,
                    'estimated_duration_minutes' => 60,
                    'price' => 800,
                ],
            ]),
        ]);

        $res = $this->submitOnboard($this->enquiry->id, $payload);
        $res->assertStatus(201);

        $salon = Salon::where('enquiry_id', $this->enquiry->id)->firstOrFail();
        $thisSalonTemplate = ServiceTemplate::where('created_by_salon_id', $salon->id)->firstOrFail();

        // Must be a separate template owned by this salon, NOT the foreign template ID!
        $this->assertNotEquals($foreignCustomTemplate->id, $thisSalonTemplate->id);
        $this->assertEquals($salon->id, $thisSalonTemplate->created_by_salon_id);
    }

    /** 11: Legitimate services in distinct categories or supported variants remain possible */
    public function test_legitimate_services_in_distinct_categories_remain_allowed(): void
    {
        Sanctum::actingAs($this->collaborator);

        // Same custom name "Express Cleanse" in two distinct categories
        $payload = $this->basePayload([
            'services' => json_encode([
                [
                    'custom_template_name' => 'Express Cleanse',
                    'category_id' => $this->standardCategory->id, // Hair Styling
                    'estimated_duration_minutes' => 20,
                    'price' => 200,
                ],
                [
                    'custom_template_name' => 'Express Cleanse',
                    'category_id' => $this->otherStandardCategory->id, // Facial Care
                    'estimated_duration_minutes' => 25,
                    'price' => 350,
                ],
            ]),
        ]);

        $res = $this->submitOnboard($this->enquiry->id, $payload);
        $res->assertStatus(201);

        $salon = Salon::where('enquiry_id', $this->enquiry->id)->firstOrFail();
        $this->assertEquals(2, Service::where('salon_id', $salon->id)->count());
    }

    /** 12: Collaborator authorization and salon scoping remain enforced */
    public function test_unauthorized_collaborator_cannot_onboard_unassigned_enquiry(): void
    {
        $otherCollaborator = User::create([
            'name' => 'Other Collab',
            'phone' => '9' . rand(100000000, 999999999),
            'role' => 'collaborator',
            'password_hash' => Hash::make('secret'),
            'is_active' => true,
        ]);

        Sanctum::actingAs($otherCollaborator);

        $payload = $this->basePayload();
        $response = $this->submitOnboard($this->enquiry->id, $payload);

        $response->assertStatus(403);
    }

    /** 13: New salon onboarding continues to work end to end */
    public function test_new_salon_onboarding_continues_to_work(): void
    {
        Sanctum::actingAs($this->collaborator);

        $payload = $this->basePayload([
            'services' => json_encode([
                ['template_id' => $this->templateA->id, 'price' => 450],
            ]),
        ]);

        $res = $this->submitOnboard($this->enquiry->id, $payload);
        $res->assertStatus(201)
            ->assertJsonPath('success', true);

        $salon = Salon::where('enquiry_id', $this->enquiry->id)->first();
        $this->assertNotNull($salon);
        $this->assertEquals('pending_approval', $salon->status);
        $this->assertEquals(1, Service::where('salon_id', $salon->id)->count());
    }

    /** 14: Existing approved-salon service management is unaffected */
    public function test_approved_salon_services_are_not_modified_by_onboard(): void
    {
        Sanctum::actingAs($this->collaborator);

        // 1. Onboard initial salon
        $payload = $this->basePayload([
            'services' => json_encode([
                ['template_id' => $this->templateA->id, 'price' => 300],
            ]),
        ]);
        $this->submitOnboard($this->enquiry->id, $payload)->assertStatus(201);

        $salon = Salon::where('enquiry_id', $this->enquiry->id)->firstOrFail();
        $originalService = Service::where('salon_id', $salon->id)->firstOrFail();

        // 2. Mark salon as approved (active)
        $salon->update(['status' => 'active']);

        // 3. Collaborator attempts to replay onboarding submission modifying services
        $retryPayload = $this->basePayload([
            'services' => json_encode([
                ['template_id' => $this->templateA->id, 'price' => 999],
                ['template_id' => $this->templateB->id, 'price' => 888],
            ]),
        ]);
        $res = $this->submitOnboard($this->enquiry->id, $retryPayload);
        $res->assertStatus(200)
            ->assertJsonPath('already_submitted', true);

        // Verify active approved salon services were NOT modified
        $currentServices = Service::where('salon_id', $salon->id)->get();
        $this->assertCount(1, $currentServices);
        $this->assertEquals(300.0, (float) $currentServices->first()->price);
    }

    /** 15: Transaction boundaries prevent inconsistent state */
    public function test_failure_rolls_back_cleanly_without_partial_writes(): void
    {
        Sanctum::actingAs($this->collaborator);

        // Payload with invalid working hours (close before open)
        $payload = $this->basePayload([
            'working_hours' => json_encode([
                ['day_of_week' => 1, 'is_closed' => false, 'open_time' => '18:00', 'close_time' => '10:00'],
            ]),
            'services' => json_encode([
                ['template_id' => $this->templateA->id, 'price' => 300],
            ]),
        ]);

        $res = $this->submitOnboard($this->enquiry->id, $payload);
        $res->assertStatus(422);

        // Verify no salon or services were persisted
        $this->assertFalse(Salon::where('enquiry_id', $this->enquiry->id)->exists());
    }

    /** Collaborator cannot select a custom template owned by another salon */
    public function test_collaborator_cannot_submit_foreign_custom_template_id(): void
    {
        Sanctum::actingAs($this->collaborator);

        $otherOwner = User::create([
            'name' => 'Other Owner',
            'phone' => '9' . rand(100000000, 999999999),
            'role' => 'salon_owner',
            'password_hash' => 'x',
            'is_active' => true,
        ]);
        $otherSalon = Salon::create([
            'name' => 'Foreign Salon',
            'slug' => 'foreign-salon-' . uniqid(),
            'admin_id' => $otherOwner->id,
            'submitted_by' => $otherOwner->id,
            'city_id' => $this->city->id,
            'address' => 'Foreign Address',
            'pincode' => '411045',
            'status' => 'pending_approval',
        ]);

        $foreignCustomTemplate = ServiceTemplate::create([
            'category_id' => $this->standardCategory->id,
            'name' => 'Foreign Salon Only Treatment',
            'estimated_duration_minutes' => 45,
            'is_custom' => true,
            'created_by_salon_id' => $otherSalon->id,
            'is_active' => true,
        ]);

        $payload = $this->basePayload([
            'services' => json_encode([
                ['template_id' => $foreignCustomTemplate->id, 'price' => 500],
            ]),
        ]);

        $res = $this->submitOnboard($this->enquiry->id, $payload);
        $res->assertStatus(422)
            ->assertJsonValidationErrors(['services.0.template_id']);
    }

    /** Custom service duplicating a standard template selected in the same category is rejected */
    public function test_custom_service_duplicating_selected_standard_template_in_same_category_is_rejected(): void
    {
        Sanctum::actingAs($this->collaborator);

        $payload = $this->basePayload([
            'services' => json_encode([
                ['template_id' => $this->templateA->id, 'price' => 300],
                [
                    'custom_template_name' => strtolower($this->templateA->name), // Matches templateA name
                    'category_id' => $this->standardCategory->id, // Same category
                    'estimated_duration_minutes' => 30,
                    'price' => 320,
                ],
            ]),
        ]);

        $res = $this->submitOnboard($this->enquiry->id, $payload);
        $res->assertStatus(422)
            ->assertJsonValidationErrors(['services.1.custom_template_name']);
    }
}
