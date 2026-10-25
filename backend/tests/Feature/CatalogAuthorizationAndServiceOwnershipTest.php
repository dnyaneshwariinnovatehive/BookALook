<?php

namespace Tests\Feature;

use App\Models\Salon;
use App\Models\SalonSubscription;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceTemplate;
use App\Models\SubscriptionPlan;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Who may change the master catalog, and what a salon may build on top of it.
 *
 * The master catalog is shared by every salon, so only the platform owner
 * edits it. A salon owner works on their own salon only: they see their own
 * custom catalog entries and nobody else's, and remove services from their
 * own salon and nobody else's.
 */
class CatalogAuthorizationAndServiceOwnershipTest extends TestCase
{
    use DatabaseTransactions;

    private User $superadmin;
    private User $owner;
    private User $otherOwner;
    private User $customer;
    private Salon $salon;
    private Salon $otherSalon;
    private ServiceCategory $category;
    private ServiceTemplate $template;
    private string $unique;

    protected function setUp(): void
    {
        parent::setUp();

        $this->unique = substr(bin2hex(random_bytes(6)), 0, 8);

        $this->superadmin = $this->makeUser('superadmin', 'sa');
        $this->owner = $this->makeUser('admin', 'own');
        $this->otherOwner = $this->makeUser('admin', 'oth');
        $this->customer = $this->makeUser('customer', 'cus');

        $this->salon = $this->makeSalon($this->owner, 'a');
        $this->otherSalon = $this->makeSalon($this->otherOwner, 'b');

        $this->category = ServiceCategory::create([
            'name' => "Hair {$this->unique}",
            'is_custom' => false,
            'is_active' => true,
        ]);

        $this->template = ServiceTemplate::create([
            'category_id' => $this->category->id,
            'name' => "Haircut {$this->unique}",
            'estimated_duration_minutes' => 30,
            'is_custom' => false,
            'is_active' => true,
        ]);
    }

    private function makeUser(string $role, string $tag): User
    {
        return User::create([
            'id' => (string) Str::uuid(),
            'name' => "{$role} {$this->unique}",
            'phone' => '9' . substr((string) crc32($this->unique . $tag), 0, 9),
            'password_hash' => bcrypt('password'),
            'role' => $role,
            'is_active' => true,
        ]);
    }

    private function makeSalon(User $owner, string $tag): Salon
    {
        $salon = Salon::create([
            'id' => (string) Str::uuid(),
            'admin_id' => $owner->id,
            'name' => "Salon {$tag} {$this->unique}",
            'slug' => "salon-{$tag}-{$this->unique}",
            'address' => '123 Market Street',
            'submitted_by' => $owner->id,
            'status' => 'active',
        ]);

        $plan = SubscriptionPlan::first() ?? SubscriptionPlan::create([
            'name' => 'Growth Plan',
            'price' => 999.00,
            'duration_days' => 30,
            'is_active' => true,
        ]);

        SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'billing_type' => \App\Support\BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => $plan->price,
            'start_date' => now()->subDays(5)->toDateString(),
            'end_date' => now()->addDays(25)->toDateString(),
            'status' => 'active',
        ]);

        return $salon;
    }

    private function customCategoryOf(Salon $salon): ServiceCategory
    {
        return ServiceCategory::create([
            'name' => "Own {$salon->slug}",
            'is_custom' => true,
            'created_by_salon_id' => $salon->id,
            'is_active' => true,
        ]);
    }

    private function customTemplateOf(Salon $salon, ServiceCategory $category): ServiceTemplate
    {
        return ServiceTemplate::create([
            'category_id' => $category->id,
            'name' => "Signature {$salon->slug}",
            'estimated_duration_minutes' => 60,
            'is_custom' => true,
            'created_by_salon_id' => $salon->id,
            'is_active' => true,
        ]);
    }

    // ── Master catalog: superadmin only ──────────────────────────────────

    public function test_salon_owner_cannot_change_the_master_catalog(): void
    {
        $custom = $this->customCategoryOf($this->salon);
        Sanctum::actingAs($this->owner);

        $this->getJson('/api/superadmin/catalog')->assertStatus(403);
        $this->postJson('/api/superadmin/catalog/categories', ['name' => 'Hijack'])->assertStatus(403);
        $this->postJson('/api/superadmin/catalog/templates', [
            'category_id' => $this->category->id,
            'name' => 'Hijack',
            'estimated_duration_minutes' => 30,
        ])->assertStatus(403);
        $this->putJson("/api/superadmin/catalog/categories/{$this->category->id}", ['name' => 'Hijack'])->assertStatus(403);
        $this->putJson("/api/superadmin/catalog/templates/{$this->template->id}", [
            'name' => 'Hijack',
            'estimated_duration_minutes' => 30,
        ])->assertStatus(403);
        $this->putJson("/api/superadmin/catalog/categories/{$custom->id}/promote")->assertStatus(403);
        $this->deleteJson("/api/superadmin/catalog/templates/{$this->template->id}")->assertStatus(403);
        $this->deleteJson("/api/superadmin/catalog/categories/{$this->category->id}")->assertStatus(403);

        $this->assertDatabaseHas('service_categories', ['id' => $this->category->id, 'name' => $this->category->name, 'deleted_at' => null]);
        $this->assertDatabaseHas('service_templates', ['id' => $this->template->id, 'name' => $this->template->name, 'deleted_at' => null]);
        $this->assertDatabaseHas('service_categories', ['id' => $custom->id, 'is_custom' => true]);
        $this->assertDatabaseMissing('service_categories', ['name' => 'Hijack']);
    }

    public function test_customer_cannot_change_the_master_catalog(): void
    {
        Sanctum::actingAs($this->customer);

        $this->postJson('/api/superadmin/catalog/categories', ['name' => 'Hijack'])->assertStatus(403);
        $this->deleteJson("/api/superadmin/catalog/categories/{$this->category->id}")->assertStatus(403);
    }

    public function test_superadmin_can_create_categories_and_templates(): void
    {
        Sanctum::actingAs($this->superadmin);

        $cat = $this->postJson('/api/superadmin/catalog/categories', ['name' => "Nails {$this->unique}"])
            ->assertStatus(200)
            ->json('category');

        $this->postJson('/api/superadmin/catalog/templates', [
            'category_id' => $cat['id'],
            'name' => 'Manicure',
            'estimated_duration_minutes' => 30,
        ])->assertStatus(200);
    }

    public function test_template_for_missing_or_retired_category_is_rejected(): void
    {
        Sanctum::actingAs($this->superadmin);

        $this->postJson('/api/superadmin/catalog/templates', [
            'category_id' => (string) Str::uuid(),
            'name' => 'Ghost',
            'estimated_duration_minutes' => 30,
        ])->assertStatus(422)->assertJsonValidationErrors('category_id', 'errors');

        $retired = ServiceCategory::create(['name' => "Gone {$this->unique}", 'is_active' => true]);
        $retired->delete();

        $this->postJson('/api/superadmin/catalog/templates', [
            'category_id' => $retired->id,
            'name' => 'Ghost',
            'estimated_duration_minutes' => 30,
        ])->assertStatus(422)->assertJsonValidationErrors('category_id', 'errors');
    }

    public function test_updating_a_category_without_an_icon_keeps_the_icon(): void
    {
        $this->category->update(['icon_url' => 'https://cdn.example.com/hair.png']);
        Sanctum::actingAs($this->superadmin);

        $this->putJson("/api/superadmin/catalog/categories/{$this->category->id}", [
            'name' => 'Hair & Beard',
            'is_active' => false,
        ])->assertStatus(200);

        $this->category->refresh();
        $this->assertSame('https://cdn.example.com/hair.png', $this->category->icon_url);
        $this->assertSame('Hair & Beard', $this->category->name);
        $this->assertFalse((bool) $this->category->is_active);

        // Naming the icon as null still clears it on purpose.
        $this->putJson("/api/superadmin/catalog/categories/{$this->category->id}", [
            'name' => 'Hair & Beard',
            'icon_url' => null,
        ])->assertStatus(200);

        $this->assertNull($this->category->refresh()->icon_url);
    }

    // ── Partner master catalog: scoped to the owner's salon ──────────────

    public function test_master_catalog_shows_own_custom_entries_and_hides_others(): void
    {
        $own = $this->customCategoryOf($this->salon);
        $ownTpl = $this->customTemplateOf($this->salon, $own);
        $theirs = $this->customCategoryOf($this->otherSalon);
        $theirTpl = $this->customTemplateOf($this->otherSalon, $this->category);

        Sanctum::actingAs($this->owner);
        $categories = collect(
            $this->getJson("/api/partner/salons/{$this->salon->id}/master-catalog")
                ->assertStatus(200)
                ->json('categories')
        );

        $this->assertTrue($categories->contains('id', $own->id));
        $this->assertFalse($categories->contains('id', $theirs->id));

        $templateIds = $categories->flatMap(fn ($c) => collect($c['templates'])->pluck('id'));
        $this->assertTrue($templateIds->contains($ownTpl->id));
        $this->assertTrue($templateIds->contains($this->template->id));
        $this->assertFalse($templateIds->contains($theirTpl->id));
    }

    public function test_master_catalog_ignores_a_salon_id_in_the_query_string(): void
    {
        $theirs = $this->customCategoryOf($this->otherSalon);
        Sanctum::actingAs($this->owner);

        $categories = collect(
            $this->getJson("/api/partner/salons/{$this->salon->id}/master-catalog?salon_id={$this->otherSalon->id}")
                ->assertStatus(200)
                ->json('categories')
        );

        $this->assertFalse($categories->contains('id', $theirs->id));
    }

    public function test_master_catalog_of_another_salon_is_forbidden(): void
    {
        Sanctum::actingAs($this->owner);

        $this->getJson("/api/partner/salons/{$this->otherSalon->id}/master-catalog")->assertStatus(403);
    }

    // ── Adding a service: only from what the salon may use ───────────────

    public function test_cannot_add_another_salons_custom_template(): void
    {
        $theirTpl = $this->customTemplateOf($this->otherSalon, $this->category);
        Sanctum::actingAs($this->owner);

        $this->postJson("/api/partner/salons/{$this->salon->id}/services", [
            'is_custom' => false,
            'template_id' => $theirTpl->id,
            'price' => 500,
        ])->assertStatus(404);

        $this->assertDatabaseMissing('services', ['salon_id' => $this->salon->id, 'template_id' => $theirTpl->id]);
    }

    public function test_can_add_own_custom_template(): void
    {
        $ownTpl = $this->customTemplateOf($this->salon, $this->category);
        Sanctum::actingAs($this->owner);

        $this->postJson("/api/partner/salons/{$this->salon->id}/services", [
            'is_custom' => false,
            'template_id' => $ownTpl->id,
            'price' => 500,
        ])->assertStatus(200);
    }

    public function test_cannot_add_inactive_template_or_template_in_inactive_category(): void
    {
        Sanctum::actingAs($this->owner);

        $this->template->update(['is_active' => false]);
        $this->postJson("/api/partner/salons/{$this->salon->id}/services", [
            'is_custom' => false,
            'template_id' => $this->template->id,
            'price' => 300,
        ])->assertStatus(404);

        $this->template->update(['is_active' => true]);
        $this->category->update(['is_active' => false]);
        $this->postJson("/api/partner/salons/{$this->salon->id}/services", [
            'is_custom' => false,
            'template_id' => $this->template->id,
            'price' => 300,
        ])->assertStatus(404);
    }

    public function test_custom_service_cannot_go_into_another_salons_category(): void
    {
        $theirs = $this->customCategoryOf($this->otherSalon);
        Sanctum::actingAs($this->owner);

        $this->postJson("/api/partner/salons/{$this->salon->id}/services", [
            'is_custom' => true,
            'category_id' => $theirs->id,
            'custom_template_name' => 'Sneaky Cut',
            'estimated_duration_minutes' => 30,
            'price' => 300,
        ])->assertStatus(422)->assertJsonValidationErrors('category_id', 'errors');

        $this->assertDatabaseMissing('service_templates', ['name' => 'Sneaky Cut']);
    }

    public function test_custom_service_into_unknown_category_is_rejected_not_a_500(): void
    {
        Sanctum::actingAs($this->owner);

        foreach ([(string) Str::uuid(), 'not-a-uuid'] as $categoryId) {
            $this->postJson("/api/partner/salons/{$this->salon->id}/services", [
                'is_custom' => true,
                'category_id' => $categoryId,
                'custom_template_name' => 'Ghost Cut',
                'estimated_duration_minutes' => 30,
                'price' => 300,
            ])->assertStatus(422);
        }

        $this->assertDatabaseMissing('service_templates', ['name' => 'Ghost Cut']);
    }

    public function test_custom_service_into_own_custom_category_works(): void
    {
        $own = $this->customCategoryOf($this->salon);
        Sanctum::actingAs($this->owner);

        $this->postJson("/api/partner/salons/{$this->salon->id}/services", [
            'is_custom' => true,
            'category_id' => $own->id,
            'custom_template_name' => 'House Special',
            'estimated_duration_minutes' => 60,
            'price' => 900,
        ])->assertStatus(200);

        $this->assertDatabaseHas('service_templates', [
            'name' => 'House Special',
            'category_id' => $own->id,
            'created_by_salon_id' => $this->salon->id,
        ]);
    }

    public function test_failed_custom_add_leaves_no_orphan_category_or_template(): void
    {
        Sanctum::actingAs($this->owner);

        // Fail after the category and template are written, while the service is.
        Service::creating(function () {
            throw new \RuntimeException('Simulated failure');
        });

        try {
            $this->postJson("/api/partner/salons/{$this->salon->id}/services", [
                'is_custom' => true,
                'category_id' => 'new_custom',
                'custom_category_name' => "Orphan Cat {$this->unique}",
                'custom_template_name' => "Orphan Tpl {$this->unique}",
                'estimated_duration_minutes' => 30,
                'price' => 300,
            ])->assertStatus(500);
        } finally {
            Service::flushEventListeners();
        }

        $this->assertDatabaseMissing('service_categories', ['name' => "Orphan Cat {$this->unique}"]);
        $this->assertDatabaseMissing('service_templates', ['name' => "Orphan Tpl {$this->unique}"]);
    }

    // ── Deleting a service: own salon only ───────────────────────────────

    public function test_salon_owner_can_delete_a_service_from_their_own_salon_only(): void
    {
        $mine = Service::create([
            'salon_id' => $this->salon->id,
            'template_id' => $this->template->id,
            'price' => 300,
        ]);
        $theirs = Service::create([
            'salon_id' => $this->otherSalon->id,
            'template_id' => $this->template->id,
            'price' => 300,
        ]);

        Sanctum::actingAs($this->owner);

        // Another salon's service, by its own path or smuggled under mine.
        $this->deleteJson("/api/partner/salons/{$this->otherSalon->id}/services/{$theirs->id}")->assertStatus(403);
        $this->deleteJson("/api/partner/salons/{$this->salon->id}/services/{$theirs->id}")->assertStatus(404);
        $this->assertNotSoftDeleted('services', ['id' => $theirs->id]);

        $this->deleteJson("/api/partner/salons/{$this->salon->id}/services/{$mine->id}")->assertStatus(200);
        $this->assertSoftDeleted('services', ['id' => $mine->id]);

        // The master template is untouched: deleting is per salon.
        $this->assertNotSoftDeleted('service_templates', ['id' => $this->template->id]);
    }
}
