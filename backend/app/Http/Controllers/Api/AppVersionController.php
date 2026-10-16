<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AppRelease;
use App\Models\AppUpdatePolicy;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;

class AppVersionController extends Controller
{
    /**
     * Return public update policy for the specified app (customer or partner).
     */
    public function show(Request $request, string $app): JsonResponse
    {
        $app = strtolower(trim($app));

        if (! in_array($app, AppRelease::APPS, true)) {
            return response()->json([
                'success' => false,
                'message' => "Invalid app identifier '{$app}'. Supported apps are: " . implode(', ', AppRelease::APPS),
            ], 404);
        }

        $platform = strtolower((string) $request->query('platform', ''));

        $cacheKey = "app_version_policy_{$app}";
        $data = Cache::remember($cacheKey, 300, function () use ($app) {
            $policy = AppUpdatePolicy::with(['latestRelease', 'minimumRelease'])
                ->where('app', $app)
                ->first();

            if (! $policy) {
                return [
                    'app' => $app,
                    'has_policy' => false,
                    'enforcement_active' => false,
                    'update_mode' => 'optional',
                    'message' => null,
                    'latest' => null,
                    'minimum' => null,
                    'store_urls' => [
                        'android' => null,
                        'ios' => null,
                    ],
                ];
            }

            return [
                'app' => $app,
                'has_policy' => true,
                'enforcement_active' => $policy->isEnforcementActive(),
                'update_mode' => $policy->update_mode,
                'enforce_at' => $policy->enforce_at?->toIso8601String(),
                'message' => $policy->update_message,
                'latest' => $policy->latestRelease ? [
                    'id' => $policy->latestRelease->id,
                    'version' => $policy->latestRelease->version,
                    'build_number' => $policy->latestRelease->build_number,
                    'released_at' => $policy->latestRelease->released_at?->toIso8601String(),
                    'release_notes' => $policy->latestRelease->release_notes,
                    'status' => $policy->latestRelease->status,
                ] : null,
                'minimum' => $policy->minimumRelease ? [
                    'id' => $policy->minimumRelease->id,
                    'version' => $policy->minimumRelease->version,
                    'build_number' => $policy->minimumRelease->build_number,
                    'released_at' => $policy->minimumRelease->released_at?->toIso8601String(),
                    'status' => $policy->minimumRelease->status,
                ] : null,
                'store_urls' => [
                    'android' => $policy->resolveAndroidStoreUrl(),
                    'ios' => $policy->resolveIosStoreUrl(),
                ],
            ];
        });

        // Add optional platform-specific store_url helper for convenience
        $storeUrl = match ($platform) {
            'android' => $data['store_urls']['android'] ?? null,
            'ios' => $data['store_urls']['ios'] ?? null,
            default => null,
        };

        return response()->json([
            'success' => true,
            ...$data,
            'store_url' => $storeUrl,
        ]);
    }
}
