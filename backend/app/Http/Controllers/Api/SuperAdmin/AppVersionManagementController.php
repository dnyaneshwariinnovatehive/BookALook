<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\AppRelease;
use App\Models\AppUpdatePolicy;
use App\Models\AuditLog;
use App\Services\AuditLogger;
use App\Support\AppVersionComparator;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class AppVersionManagementController extends Controller
{
    /**
     * Get all releases, active policies, and recent audit trail for version management.
     */
    public function index(Request $request): JsonResponse
    {
        $appFilter = $request->query('app');

        $releasesQuery = AppRelease::with(['creator:id,name', 'updater:id,name'])
            ->orderBy('released_at', 'desc')
            ->orderBy('created_at', 'desc');

        if ($appFilter && in_array($appFilter, AppRelease::APPS, true)) {
            $releasesQuery->where('app', $appFilter);
        }

        $releases = $releasesQuery->get();

        $policies = AppUpdatePolicy::with(['latestRelease', 'minimumRelease', 'updater:id,name'])
            ->get()
            ->keyBy('app');

        // Ensure both customer and partner policies exist in response
        $allPolicies = [];
        foreach (AppRelease::APPS as $appKey) {
            $policy = $policies->get($appKey);
            $allPolicies[$appKey] = $policy ? [
                'id' => $policy->id,
                'app' => $policy->app,
                'latest_release_id' => $policy->latest_release_id,
                'minimum_release_id' => $policy->minimum_release_id,
                'update_mode' => $policy->update_mode,
                'is_enforced' => $policy->is_enforced,
                'enforce_at' => $policy->enforce_at?->toIso8601String(),
                'update_message' => $policy->update_message,
                'android_store_url' => $policy->android_store_url,
                'ios_store_url' => $policy->ios_store_url,
                'resolved_android_url' => $policy->resolveAndroidStoreUrl(),
                'resolved_ios_url' => $policy->resolveIosStoreUrl(),
                'is_active' => $policy->isEnforcementActive(),
                'latest_release' => $policy->latestRelease,
                'minimum_release' => $policy->minimumRelease,
                'updated_by' => $policy->updater?->name,
                'updated_at' => $policy->updated_at?->toIso8601String(),
            ] : null;
        }

        $auditHistory = AuditLog::with('actor:id,name')
            ->whereIn('action', [
                AuditLog::APP_RELEASE_CREATED,
                AuditLog::APP_RELEASE_UPDATED,
                AuditLog::APP_UPDATE_POLICY_UPDATED,
            ])
            ->latest()
            ->take(25)
            ->get()
            ->map(function ($log) {
                return [
                    'id' => $log->id,
                    'action' => $log->action,
                    'actor' => $log->actor?->name ?? 'System',
                    'label' => $log->subjectLabel() ?? $log->describe()['label'],
                    'before' => $log->old_value,
                    'after' => $log->new_value,
                    'metadata' => $log->metadata,
                    'created_at' => $log->created_at?->toIso8601String(),
                ];
            });

        return response()->json([
            'success' => true,
            'releases' => $releases,
            'policies' => $allPolicies,
            'audit_history' => $auditHistory,
        ]);
    }

    /**
     * Register a new app release.
     */
    public function storeRelease(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'app' => ['required', 'string', Rule::in(AppRelease::APPS)],
            'version' => ['required', 'string', 'max:50'],
            'build_number' => ['required', 'integer', 'min:1'],
            'released_at' => ['nullable', 'date'],
            'release_notes' => ['nullable', 'string'],
            'android_store_url' => ['nullable', 'string', 'max:500', 'url'],
            'ios_store_url' => ['nullable', 'string', 'max:500', 'url'],
            'status' => ['required', 'string', Rule::in(AppRelease::STATUSES)],
        ]);

        $existing = AppRelease::where('app', $validated['app'])
            ->where('version', $validated['version'])
            ->where('build_number', $validated['build_number'])
            ->first();

        if ($existing) {
            throw ValidationException::withMessages([
                'version' => ["A release for {$validated['app']} app with version {$validated['version']} and build {$validated['build_number']} already exists."],
            ]);
        }

        $admin = $request->user();

        $release = AppRelease::create([
            ...$validated,
            'released_at' => $validated['released_at'] ?? now(),
            'created_by' => $admin?->id,
            'updated_by' => $admin?->id,
        ]);

        AuditLogger::record(
            action: AuditLog::APP_RELEASE_CREATED,
            entity: $release,
            label: "Registered {$release->app} app release v{$release->version} (#{$release->build_number})",
            before: null,
            after: [
                'app' => $release->app,
                'version' => $release->version,
                'build_number' => $release->build_number,
                'status' => $release->status,
                'released_at' => $release->released_at?->toIso8601String(),
            ]
        );

        Cache::forget("app_version_policy_{$release->app}");

        return response()->json([
            'success' => true,
            'message' => 'Release registered successfully.',
            'release' => $release->load(['creator:id,name', 'updater:id,name']),
        ], 201);
    }

    /**
     * Update an existing app release.
     */
    public function updateRelease(Request $request, string $id): JsonResponse
    {
        $release = AppRelease::findOrFail($id);

        $validated = $request->validate([
            'version' => ['sometimes', 'required', 'string', 'max:50'],
            'build_number' => ['sometimes', 'required', 'integer', 'min:1'],
            'released_at' => ['nullable', 'date'],
            'release_notes' => ['nullable', 'string'],
            'android_store_url' => ['nullable', 'string', 'max:500', 'url'],
            'ios_store_url' => ['nullable', 'string', 'max:500', 'url'],
            'status' => ['sometimes', 'required', 'string', Rule::in(AppRelease::STATUSES)],
        ]);

        $newVersion = $validated['version'] ?? $release->version;
        $newBuild = isset($validated['build_number']) ? (int) $validated['build_number'] : $release->build_number;

        if ($newVersion !== $release->version || $newBuild !== $release->build_number) {
            $duplicate = AppRelease::where('app', $release->app)
                ->where('version', $newVersion)
                ->where('build_number', $newBuild)
                ->where('id', '!=', $release->id)
                ->first();

            if ($duplicate) {
                throw ValidationException::withMessages([
                    'version' => ["Another {$release->app} release already exists with version {$newVersion} and build {$newBuild}."],
                ]);
            }
        }

        // If retiring or setting to draft, prevent if it's currently selected in active policy
        if (isset($validated['status']) && $validated['status'] !== AppRelease::STATUS_PUBLISHED) {
            $isUsedInPolicy = AppUpdatePolicy::where('app', $release->app)
                ->where(function ($q) use ($release) {
                    $q->where('latest_release_id', $release->id)
                      ->orWhere('minimum_release_id', $release->id);
                })
                ->exists();

            if ($isUsedInPolicy) {
                throw ValidationException::withMessages([
                    'status' => ["Cannot change status to '{$validated['status']}' because this release is currently selected in the active policy for {$release->app} app. Please update the policy first."],
                ]);
            }
        }

        $before = [
            'version' => $release->version,
            'build_number' => $release->build_number,
            'status' => $release->status,
            'released_at' => $release->released_at?->toIso8601String(),
            'release_notes' => $release->release_notes,
            'android_store_url' => $release->android_store_url,
            'ios_store_url' => $release->ios_store_url,
        ];

        $admin = $request->user();
        $release->fill($validated);
        $release->updated_by = $admin?->id;
        $release->save();

        $after = [
            'version' => $release->version,
            'build_number' => $release->build_number,
            'status' => $release->status,
            'released_at' => $release->released_at?->toIso8601String(),
            'release_notes' => $release->release_notes,
            'android_store_url' => $release->android_store_url,
            'ios_store_url' => $release->ios_store_url,
        ];

        if ($before !== $after) {
            AuditLogger::record(
                action: AuditLog::APP_RELEASE_UPDATED,
                entity: $release,
                label: "Updated {$release->app} app release v{$release->version} (#{$release->build_number})",
                before: $before,
                after: $after
            );
        }

        Cache::forget("app_version_policy_{$release->app}");

        return response()->json([
            'success' => true,
            'message' => 'Release updated successfully.',
            'release' => $release->load(['creator:id,name', 'updater:id,name']),
        ]);
    }

    /**
     * Update or set the update policy for an app (customer or partner).
     */
    public function updatePolicy(Request $request, string $app): JsonResponse
    {
        $app = strtolower(trim($app));
        if (! in_array($app, AppRelease::APPS, true)) {
            return response()->json([
                'success' => false,
                'message' => "Invalid app identifier '{$app}'. Supported apps are: " . implode(', ', AppRelease::APPS),
            ], 404);
        }

        $validated = $request->validate([
            'latest_release_id' => ['required', 'uuid', 'exists:app_releases,id'],
            'minimum_release_id' => ['required', 'uuid', 'exists:app_releases,id'],
            'update_mode' => ['required', 'string', Rule::in(AppUpdatePolicy::MODES)],
            'is_enforced' => ['required', 'boolean'],
            'enforce_at' => ['nullable', 'date'],
            'update_message' => ['nullable', 'string'],
            'android_store_url' => ['nullable', 'string', 'max:500', 'url'],
            'ios_store_url' => ['nullable', 'string', 'max:500', 'url'],
        ]);

        $latest = AppRelease::findOrFail($validated['latest_release_id']);
        $minimum = AppRelease::findOrFail($validated['minimum_release_id']);

        // App separation validation
        if ($latest->app !== $app || $minimum->app !== $app) {
            throw ValidationException::withMessages([
                'latest_release_id' => ["Selected release does not belong to the '{$app}' app."],
            ]);
        }

        // Must be published releases
        if ($latest->status !== AppRelease::STATUS_PUBLISHED) {
            throw ValidationException::withMessages([
                'latest_release_id' => ["Latest release must be 'published'. Selected release has status '{$latest->status}'."],
            ]);
        }

        if ($minimum->status !== AppRelease::STATUS_PUBLISHED) {
            throw ValidationException::withMessages([
                'minimum_release_id' => ["Minimum supported release must be 'published'. Selected release has status '{$minimum->status}'."],
            ]);
        }

        // Semantic version validation: minimum must NOT be greater than latest
        if (AppVersionComparator::compareReleases($minimum, $latest) > 0) {
            throw ValidationException::withMessages([
                'minimum_release_id' => [
                    "Minimum supported version (v{$minimum->version} #{$minimum->build_number}) cannot be higher than latest published version (v{$latest->version} #{$latest->build_number}).",
                ],
            ]);
        }

        $policy = AppUpdatePolicy::firstOrNew(['app' => $app]);

        $before = $policy->exists ? [
            'latest_release_id' => $policy->latest_release_id,
            'minimum_release_id' => $policy->minimum_release_id,
            'update_mode' => $policy->update_mode,
            'is_enforced' => (bool) $policy->is_enforced,
            'enforce_at' => $policy->enforce_at?->toIso8601String(),
            'update_message' => $policy->update_message,
            'android_store_url' => $policy->android_store_url,
            'ios_store_url' => $policy->ios_store_url,
        ] : null;

        $admin = $request->user();
        $policy->fill($validated);
        $policy->updated_by = $admin?->id;
        $policy->save();

        $after = [
            'latest_release_id' => $policy->latest_release_id,
            'minimum_release_id' => $policy->minimum_release_id,
            'update_mode' => $policy->update_mode,
            'is_enforced' => (bool) $policy->is_enforced,
            'enforce_at' => $policy->enforce_at?->toIso8601String(),
            'update_message' => $policy->update_message,
            'android_store_url' => $policy->android_store_url,
            'ios_store_url' => $policy->ios_store_url,
        ];

        // Audit log only if something actually changed
        if ($before === null || $before !== $after) {
            AuditLogger::record(
                action: AuditLog::APP_UPDATE_POLICY_UPDATED,
                entity: $policy,
                label: "Updated {$app} app update policy (enforced: " . ($policy->is_enforced ? 'yes' : 'no') . ", mode: {$policy->update_mode})",
                before: $before,
                after: $after,
                metadata: [
                    'latest_version' => $latest->version,
                    'latest_build' => $latest->build_number,
                    'minimum_version' => $minimum->version,
                    'minimum_build' => $minimum->build_number,
                ]
            );
        }

        Cache::forget("app_version_policy_{$app}");

        // Check for store URL warnings
        $warnings = [];
        if (! $policy->resolveAndroidStoreUrl()) {
            $warnings[] = "Android store URL is not configured in this policy or on release v{$latest->version}.";
        }
        if (! $policy->resolveIosStoreUrl()) {
            $warnings[] = "iOS store URL is not configured in this policy or on release v{$latest->version}.";
        }

        return response()->json([
            'success' => true,
            'message' => 'App update policy saved successfully.',
            'policy' => $policy->load(['latestRelease', 'minimumRelease', 'updater:id,name']),
            'warnings' => $warnings,
        ]);
    }
}
