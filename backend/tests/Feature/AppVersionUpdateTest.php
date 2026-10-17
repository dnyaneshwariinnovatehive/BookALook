<?php

namespace Tests\Feature;

use App\Models\AppRelease;
use App\Models\AppUpdatePolicy;
use App\Models\AuditLog;
use App\Models\User;
use App\Support\AppVersionComparator;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;
use Tests\TestCase;

class AppVersionUpdateTest extends TestCase
{
    use DatabaseTransactions;

    private User $superadmin;
    private User $customer;

    protected function setUp(): void
    {
        parent::setUp();

        $this->superadmin = $this->createUser('superadmin');
        $this->customer = $this->createUser('customer');
        Cache::flush();
    }

    /* ── 1. Semantic Version Comparator Unit / Logic ─────────── */

    public function test_semantic_version_comparator(): void
    {
        // Major / Minor / Patch comparisons
        $this->assertTrue(AppVersionComparator::isLessThan('2.3.9', 10, '2.4.0', 1));
        $this->assertTrue(AppVersionComparator::isGreaterThan('2.10.0', 1, '2.9.0', 100));
        $this->assertTrue(AppVersionComparator::isEqual('v2.4.0', 42, '2.4.0', 42));

        // Same version string, different build numbers
        $this->assertTrue(AppVersionComparator::isLessThan('2.4.0', 41, '2.4.0', 42));
        $this->assertTrue(AppVersionComparator::isGreaterThan('2.4.0', 43, '2.4.0', 42));
        $this->assertSame(0, AppVersionComparator::compare('2.4.0', 42, '2.4.0', 42));
    }

    /* ── 2. Public Configuration Endpoint ───────────────────── */

    public function test_public_endpoint_safe_defaults_when_no_policy_exists(): void
    {
        $response = $this->getJson('/api/app-version/customer');

        $response->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('app', 'customer')
            ->assertJsonPath('has_policy', false)
            ->assertJsonPath('enforcement_active', false)
            ->assertJsonPath('update_mode', 'optional')
            ->assertJsonPath('latest', null)
            ->assertJsonPath('minimum', null);
    }

    public function test_public_endpoint_rejects_arbitrary_untrusted_app_identifier(): void
    {
        $response = $this->getJson('/api/app-version/unknown_admin_app');

        $response->assertStatus(404)
            ->assertJsonPath('success', false);
    }

    public function test_public_endpoint_returns_policy_with_store_urls(): void
    {
        $release = $this->createRelease([
            'app' => 'customer',
            'version' => '2.4.0',
            'build_number' => 42,
            'status' => AppRelease::STATUS_PUBLISHED,
            'release_notes' => 'Exciting new features and bug fixes',
            'android_store_url' => 'https://play.google.com/store/apps/details?id=in.bookalook.app',
            'ios_store_url' => 'https://apps.apple.com/app/bookalook/id123456789',
        ]);

        $this->createPolicy([
            'app' => 'customer',
            'latest_release_id' => $release->id,
            'minimum_release_id' => $release->id,
            'update_mode' => 'mandatory',
            'is_enforced' => true,
            'update_message' => 'Please update to keep booking smoothly.',
        ]);

        $response = $this->getJson('/api/app-version/customer?platform=android');

        $response->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('app', 'customer')
            ->assertJsonPath('has_policy', true)
            ->assertJsonPath('enforcement_active', true)
            ->assertJsonPath('update_mode', 'mandatory')
            ->assertJsonPath('latest.version', '2.4.0')
            ->assertJsonPath('latest.build_number', 42)
            ->assertJsonPath('latest.release_notes', 'Exciting new features and bug fixes')
            ->assertJsonPath('store_urls.android', 'https://play.google.com/store/apps/details?id=in.bookalook.app')
            ->assertJsonPath('store_url', 'https://play.google.com/store/apps/details?id=in.bookalook.app');
    }

    /* ── 3. SuperAdmin Authorization ────────────────────────── */

    public function test_unauthenticated_requests_to_superadmin_endpoints_are_blocked(): void
    {
        $this->getJson('/api/superadmin/app-versions')->assertStatus(401);
        $this->postJson('/api/superadmin/app-versions/releases', [])->assertStatus(401);
        $this->putJson('/api/superadmin/app-versions/policies/customer', [])->assertStatus(401);
    }

    public function test_superadmin_can_list_app_versions_and_audit(): void
    {
        $release = $this->createRelease(['app' => 'partner', 'version' => '1.0.0', 'build_number' => 1]);

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->getJson('/api/superadmin/app-versions');

        $response->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonStructure(['releases', 'policies', 'audit_history']);
    }

    /* ── 4. Release Registration and Validation ─────────────── */

    public function test_superadmin_can_register_new_release_with_audit_trail(): void
    {
        $payload = [
            'app' => 'customer',
            'version' => '3.0.0',
            'build_number' => 100,
            'released_at' => now()->toDateString(),
            'release_notes' => 'Version 3.0 launch',
            'android_store_url' => 'https://play.google.com/store/apps/details?id=in.bookalook.app',
            'ios_store_url' => 'https://apps.apple.com/app/bookalook/id123456789',
            'status' => 'published',
        ];

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->postJson('/api/superadmin/app-versions/releases', $payload);

        $response->assertStatus(201)
            ->assertJsonPath('success', true)
            ->assertJsonPath('release.version', '3.0.0')
            ->assertJsonPath('release.build_number', 100);

        $this->assertDatabaseHas('app_releases', [
            'app' => 'customer',
            'version' => '3.0.0',
            'build_number' => 100,
            'status' => 'published',
        ]);

        $this->assertDatabaseHas('audit_log', [
            'action' => AuditLog::APP_RELEASE_CREATED,
        ]);
    }

    public function test_duplicate_release_for_same_app_is_rejected(): void
    {
        $this->createRelease(['app' => 'customer', 'version' => '2.0.0', 'build_number' => 20]);

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->postJson('/api/superadmin/app-versions/releases', [
                'app' => 'customer',
                'version' => '2.0.0',
                'build_number' => 20,
                'status' => 'draft',
            ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['version']);
    }

    public function test_cannot_retire_a_release_currently_in_use_by_policy(): void
    {
        $release = $this->createRelease(['app' => 'customer', 'version' => '2.1.0', 'build_number' => 25, 'status' => 'published']);
        $this->createPolicy([
            'app' => 'customer',
            'latest_release_id' => $release->id,
            'minimum_release_id' => $release->id,
        ]);

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->putJson("/api/superadmin/app-versions/releases/{$release->id}", [
                'status' => 'retired',
            ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['status']);
    }

    /* ── 5. Policy Configuration and Validation ─────────────── */

    public function test_policy_enforces_app_separation(): void
    {
        $partnerRelease = $this->createRelease(['app' => 'partner', 'version' => '1.5.0', 'build_number' => 15, 'status' => 'published']);
        $customerRelease = $this->createRelease(['app' => 'customer', 'version' => '1.5.0', 'build_number' => 15, 'status' => 'published']);

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->putJson('/api/superadmin/app-versions/policies/customer', [
                'latest_release_id' => $customerRelease->id,
                'minimum_release_id' => $partnerRelease->id, // Mismatched app!
                'update_mode' => 'optional',
                'is_enforced' => false,
            ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['latest_release_id']);
    }

    public function test_policy_rejects_minimum_version_higher_than_latest(): void
    {
        $latest = $this->createRelease(['app' => 'customer', 'version' => '2.4.0', 'build_number' => 42, 'status' => 'published']);
        $olderV3 = $this->createRelease(['app' => 'customer', 'version' => '2.5.0', 'build_number' => 45, 'status' => 'published']);

        // Attempt to set minimum (2.5.0 #45) higher than latest (2.4.0 #42)
        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->putJson('/api/superadmin/app-versions/policies/customer', [
                'latest_release_id' => $latest->id,
                'minimum_release_id' => $olderV3->id,
                'update_mode' => 'mandatory',
                'is_enforced' => true,
            ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['minimum_release_id']);
    }

    public function test_policy_rejects_draft_or_retired_releases(): void
    {
        $draft = $this->createRelease(['app' => 'customer', 'version' => '2.6.0', 'build_number' => 50, 'status' => 'draft']);

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->putJson('/api/superadmin/app-versions/policies/customer', [
                'latest_release_id' => $draft->id,
                'minimum_release_id' => $draft->id,
                'update_mode' => 'optional',
                'is_enforced' => false,
            ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['latest_release_id']);
    }

    public function test_superadmin_can_save_valid_policy_and_receives_store_url_warnings(): void
    {
        $r1 = $this->createRelease(['app' => 'partner', 'version' => '1.0.0', 'build_number' => 1, 'status' => 'published']);
        $r2 = $this->createRelease(['app' => 'partner', 'version' => '1.1.0', 'build_number' => 5, 'status' => 'published']);

        $response = $this->actingAs($this->superadmin, 'sanctum')
            ->putJson('/api/superadmin/app-versions/policies/partner', [
                'latest_release_id' => $r2->id,
                'minimum_release_id' => $r1->id,
                'update_mode' => 'optional',
                'is_enforced' => true,
                'update_message' => 'Partner update recommended',
            ]);

        $response->assertStatus(200)
            ->assertJsonPath('success', true)
            ->assertJsonPath('policy.latest_release_id', $r2->id)
            ->assertJsonPath('policy.minimum_release_id', $r1->id);

        $this->assertNotEmpty($response->json('warnings'));
    }

    /* ── 6. Server-Side Version Enforcement Middleware ──────── */

    public function test_outdated_app_client_is_blocked_with_426_when_enforcement_is_active(): void
    {
        $minRelease = $this->createRelease(['app' => 'customer', 'version' => '2.0.0', 'build_number' => 20, 'status' => 'published']);
        $latestRelease = $this->createRelease(['app' => 'customer', 'version' => '2.4.0', 'build_number' => 42, 'status' => 'published']);

        $this->createPolicy([
            'app' => 'customer',
            'latest_release_id' => $latestRelease->id,
            'minimum_release_id' => $minRelease->id,
            'update_mode' => 'mandatory',
            'is_enforced' => true,
            'update_message' => 'Your version of BookALook is no longer supported.',
        ]);

        // Outdated client (v1.9.0 build 15) calling customer endpoint
        $response = $this->getJson('/api/customer/categories', [
            'X-App-Id' => 'customer',
            'X-App-Version' => '1.9.0',
            'X-App-Build' => '15',
        ]);

        $response->assertStatus(426)
            ->assertHeader('X-Upgrade-Required', 'true')
            ->assertJsonPath('update_required', true)
            ->assertJsonPath('app', 'customer')
            ->assertJsonPath('current_version', '1.9.0')
            ->assertJsonPath('minimum_version', '2.0.0')
            ->assertJsonPath('minimum_build', 20)
            ->assertJsonPath('latest_version', '2.4.0')
            ->assertJsonPath('latest_build', 42);
    }

    public function test_compliant_app_client_is_allowed(): void
    {
        $minRelease = $this->createRelease(['app' => 'customer', 'version' => '2.0.0', 'build_number' => 20, 'status' => 'published']);
        $latestRelease = $this->createRelease(['app' => 'customer', 'version' => '2.4.0', 'build_number' => 42, 'status' => 'published']);

        $this->createPolicy([
            'app' => 'customer',
            'latest_release_id' => $latestRelease->id,
            'minimum_release_id' => $minRelease->id,
            'update_mode' => 'mandatory',
            'is_enforced' => true,
        ]);

        // Compliant client (v2.0.0 build 20)
        $response = $this->getJson('/api/customer/categories', [
            'X-App-Id' => 'customer',
            'X-App-Version' => '2.0.0',
            'X-App-Build' => '20',
        ]);

        $response->assertStatus(200);
    }

    public function test_disabled_enforcement_allows_older_client(): void
    {
        $minRelease = $this->createRelease(['app' => 'customer', 'version' => '2.0.0', 'build_number' => 20, 'status' => 'published']);
        $latestRelease = $this->createRelease(['app' => 'customer', 'version' => '2.4.0', 'build_number' => 42, 'status' => 'published']);

        $this->createPolicy([
            'app' => 'customer',
            'latest_release_id' => $latestRelease->id,
            'minimum_release_id' => $minRelease->id,
            'is_enforced' => false, // Enforcement turned off
        ]);

        $response = $this->getJson('/api/customer/categories', [
            'X-App-Id' => 'customer',
            'X-App-Version' => '1.0.0',
            'X-App-Build' => '1',
        ]);

        $response->assertStatus(200);
    }

    public function test_future_scheduled_enforcement_does_not_block_client_yet(): void
    {
        $minRelease = $this->createRelease(['app' => 'customer', 'version' => '2.0.0', 'build_number' => 20, 'status' => 'published']);
        $latestRelease = $this->createRelease(['app' => 'customer', 'version' => '2.4.0', 'build_number' => 42, 'status' => 'published']);

        $this->createPolicy([
            'app' => 'customer',
            'latest_release_id' => $latestRelease->id,
            'minimum_release_id' => $minRelease->id,
            'is_enforced' => true,
            'enforce_at' => Carbon::now()->addDays(7), // In the future!
        ]);

        $response = $this->getJson('/api/customer/categories', [
            'X-App-Id' => 'customer',
            'X-App-Version' => '1.0.0',
            'X-App-Build' => '1',
        ]);

        $response->assertStatus(200);
    }

    public function test_customer_enforcement_does_not_block_partner_app(): void
    {
        $custMin = $this->createRelease(['app' => 'customer', 'version' => '3.0.0', 'build_number' => 50, 'status' => 'published']);
        $this->createPolicy([
            'app' => 'customer',
            'latest_release_id' => $custMin->id,
            'minimum_release_id' => $custMin->id,
            'is_enforced' => true,
        ]);

        // Partner app version is 1.0.0 build 1, partner policy is not enforced
        $response = $this->postJson('/api/partner/auth/send-otp', [
            'phone' => '9999999999',
        ], [
            'X-App-Id' => 'partner',
            'X-App-Version' => '1.0.0',
            'X-App-Build' => '1',
        ]);

        // Partner request must not be blocked by Customer policy
        $this->assertNotSame(426, $response->getStatusCode());
    }

    public function test_exempt_paths_are_never_blocked(): void
    {
        $custMin = $this->createRelease(['app' => 'customer', 'version' => '3.0.0', 'build_number' => 50, 'status' => 'published']);
        $this->createPolicy([
            'app' => 'customer',
            'latest_release_id' => $custMin->id,
            'minimum_release_id' => $custMin->id,
            'is_enforced' => true,
        ]);

        // Version configuration endpoint itself must remain accessible to outdated client
        $response = $this->getJson('/api/app-version/customer', [
            'X-App-Id' => 'customer',
            'X-App-Version' => '1.0.0',
            'X-App-Build' => '1',
        ]);

        $response->assertStatus(200);
    }

    public function test_version_semantics_edge_cases(): void
    {
        // 2.9.0 vs 2.10.0
        $this->assertTrue(AppVersionComparator::isLessThan('2.9.0', 1, '2.10.0', 1));
        $this->assertTrue(AppVersionComparator::isGreaterThan('2.10.0', 1, '2.9.0', 1));

        // Equal visible versions with different build numbers
        $this->assertTrue(AppVersionComparator::isLessThan('2.0.0', 10, '2.0.0', 20));
        $this->assertTrue(AppVersionComparator::isGreaterThan('2.0.0', 20, '2.0.0', 10));
        $this->assertTrue(AppVersionComparator::isEqual('2.0.0', 10, '2.0.0', 10));

        // +build suffix extraction when build is passed as 0
        $this->assertTrue(AppVersionComparator::isLessThan('2.0.0+10', 0, '2.0.0+20', 0));
        $this->assertTrue(AppVersionComparator::isEqual('2.0.0+10', 0, '2.0.0', 10));

        // Boundary tests against a minimum version 2.5.0 build 50
        $minVer = '2.5.0';
        $minBuild = 50;

        // Below minimum
        $this->assertTrue(AppVersionComparator::isLessThan('2.4.9', 99, $minVer, $minBuild));
        $this->assertTrue(AppVersionComparator::isLessThan('2.5.0', 49, $minVer, $minBuild));

        // Equal to minimum
        $this->assertTrue(AppVersionComparator::isEqual('2.5.0', 50, $minVer, $minBuild));

        // Above minimum
        $this->assertTrue(AppVersionComparator::isGreaterThan('2.5.0', 51, $minVer, $minBuild));
        $this->assertTrue(AppVersionComparator::isGreaterThan('2.5.1', 1, $minVer, $minBuild));
        $this->assertTrue(AppVersionComparator::isGreaterThan('3.0.0', 1, $minVer, $minBuild));
    }

    public function test_public_endpoint_does_not_leak_secrets_or_internal_admin_data(): void
    {
        $rel = $this->createRelease([
            'status' => 'published',
            'version' => '2.5.0',
            'build_number' => 50,
            'created_by' => $this->superadmin->id,
            'updated_by' => $this->superadmin->id,
        ]);

        $this->createPolicy([
            'latest_release_id' => $rel->id,
            'minimum_release_id' => $rel->id,
            'is_enforced' => true,
            'updated_by' => $this->superadmin->id,
        ]);

        $response = $this->getJson('/api/app-version/customer');

        $response->assertStatus(200);
        $json = $response->json();

        // Must NOT leak user IDs or internal state
        $this->assertArrayNotHasKey('is_enforced', $json);
        $this->assertArrayNotHasKey('created_by', $json);
        $this->assertArrayNotHasKey('updated_by', $json);
        $this->assertArrayNotHasKey('user_id', $json);
        $this->assertArrayNotHasKey('admin', $json);
        $this->assertArrayNotHasKey('password', $json);
    }

    public function test_scheduled_enforcement_activates_when_time_passes(): void
    {
        $minRel = $this->createRelease([
            'status' => 'published',
            'version' => '2.0.0',
            'build_number' => 20,
        ]);

        // Schedule enforcement 1 hour into the future
        $futureTime = now()->addHour();
        $this->createPolicy([
            'latest_release_id' => $minRel->id,
            'minimum_release_id' => $minRel->id,
            'is_enforced' => true,
            'enforce_at' => $futureTime,
        ]);

        // 1. Before scheduled time: enforcement_active is false, older client is NOT blocked
        $response = $this->getJson('/api/app-version/customer');
        $response->assertStatus(200)->assertJsonPath('enforcement_active', false);

        $apiRes = $this->actingAs($this->customer, 'sanctum')->getJson('/api/customer/profile', [
            'X-App-Id' => 'customer',
            'X-App-Version' => '1.5.0',
            'X-App-Build' => '15',
        ]);
        $apiRes->assertStatus(200);

        // 2. Advance time past enforce_at
        Carbon::setTestNow($futureTime->copy()->addMinutes(5));

        // Dynamic check: public endpoint now reports enforcement_active = true
        $responseAfter = $this->getJson('/api/app-version/customer');
        $responseAfter->assertStatus(200)->assertJsonPath('enforcement_active', true);

        // API request is now blocked with 426
        $apiResAfter = $this->actingAs($this->customer, 'sanctum')->getJson('/api/customer/profile', [
            'X-App-Id' => 'customer',
            'X-App-Version' => '1.5.0',
            'X-App-Build' => '15',
        ]);
        $apiResAfter->assertStatus(426)->assertJsonPath('update_required', true);

        // Reset test time
        Carbon::setTestNow();
    }

    public function test_disabling_enforcement_restores_normal_access_immediately(): void
    {
        $minRel = $this->createRelease([
            'status' => 'published',
            'version' => '3.0.0',
            'build_number' => 30,
        ]);

        $policy = $this->createPolicy([
            'latest_release_id' => $minRel->id,
            'minimum_release_id' => $minRel->id,
            'is_enforced' => true,
        ]);

        // Initially blocked
        $blocked = $this->actingAs($this->customer, 'sanctum')->getJson('/api/customer/profile', [
            'X-App-Id' => 'customer',
            'X-App-Version' => '2.0.0',
            'X-App-Build' => '20',
        ]);
        $blocked->assertStatus(426);

        // SuperAdmin disables enforcement (kill switch)
        $this->actingAs($this->superadmin, 'sanctum')
            ->putJson('/api/superadmin/app-versions/policies/customer', [
                'latest_release_id' => $minRel->id,
                'minimum_release_id' => $minRel->id,
                'update_mode' => 'optional',
                'is_enforced' => false,
            ])
            ->assertStatus(200);

        // Client is immediately restored without deleting releases
        $restored = $this->actingAs($this->customer, 'sanctum')->getJson('/api/customer/profile', [
            'X-App-Id' => 'customer',
            'X-App-Version' => '2.0.0',
            'X-App-Build' => '20',
        ]);
        $restored->assertStatus(200);
    }

    /* ── Helpers ────────────────────────────────────────────── */

    private function createUser(string $role): User
    {
        $unique = Str::random(8);
        return User::create([
            'id' => (string) Str::uuid(),
            'name' => "User {$unique}",
            'phone' => '9' . substr((string) crc32($unique), 0, 9),
            'password_hash' => bcrypt('password'),
            'role' => $role,
            'is_active' => true,
        ]);
    }

    private function createRelease(array $attributes = []): AppRelease
    {
        return AppRelease::create(array_merge([
            'id' => (string) Str::uuid(),
            'app' => 'customer',
            'version' => '1.0.0',
            'build_number' => 1,
            'status' => 'draft',
            'released_at' => now(),
            'created_by' => $this->superadmin->id,
            'updated_by' => $this->superadmin->id,
        ], $attributes));
    }

    private function createPolicy(array $attributes = []): AppUpdatePolicy
    {
        return AppUpdatePolicy::create(array_merge([
            'id' => (string) Str::uuid(),
            'app' => 'customer',
            'update_mode' => 'optional',
            'is_enforced' => false,
            'updated_by' => $this->superadmin->id,
        ], $attributes));
    }
}
