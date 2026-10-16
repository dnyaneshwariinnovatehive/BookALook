<?php

namespace App\Http\Middleware;

use App\Models\AppRelease;
use App\Models\AppUpdatePolicy;
use App\Support\AppVersionComparator;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Cache;
use Symfony\Component\HttpFoundation\Response;

class EnforceAppVersion
{
    /**
     * Paths that must never be blocked by version enforcement.
     */
    protected array $exemptPaths = [
        'up',
        'api/app-version/*',
        'api/superadmin/*',
        'superadmin/*',
        'api/whatsapp/*',
        'whatsapp/*',
        'api/settlement-invoices/*',
        'settlement-invoices/*',
    ];

    /**
     * Handle an incoming request.
     */
    public function handle(Request $request, Closure $next): Response
    {
        // 1. Exemption check
        foreach ($this->exemptPaths as $exempt) {
            if ($request->is($exempt)) {
                return $next($request);
            }
        }

        // 2. Identify the app
        $app = $this->resolveAppIdentifier($request);
        if (! $app) {
            // Not a customer or partner app request; pass through safely
            return $next($request);
        }

        // 3. Extract version and build headers
        $clientVersion = $request->header('X-App-Version')
            ?? $request->header('x-app-version');

        $clientBuildHeader = $request->header('X-App-Build')
            ?? $request->header('x-app-build')
            ?? $request->header('X-Build-Number')
            ?? $request->header('x-build-number');

        $explicitAppHeader = $request->header('X-App-Id')
            ?? $request->header('x-app-id');

        // If this is not identifying as an app client and sends no version header,
        // it may be an external browser/web client calling public discovery APIs. Allow through.
        if (! $explicitAppHeader && ! $clientVersion) {
            return $next($request);
        }

        // 4. Retrieve active cached policy
        $policyData = $this->getPolicyData($app);
        if (! $policyData || ! ($policyData['has_policy'] ?? false)) {
            return $next($request);
        }

        // Check if enforcement is enabled and active (enforce_at <= now if set)
        if (! ($policyData['is_enforced'] ?? false)) {
            return $next($request);
        }

        if (! empty($policyData['enforce_at'])) {
            $enforceAt = Carbon::parse($policyData['enforce_at']);
            if (now()->lessThan($enforceAt)) {
                return $next($request);
            }
        }

        $minRelease = $policyData['minimum'] ?? null;
        if (! $minRelease) {
            return $next($request);
        }

        $minVersion = $minRelease['version'] ?? '0.0.0';
        $minBuild = (int) ($minRelease['build_number'] ?? 0);

        // If client failed to provide version while identifying as an app under active enforcement:
        if (! $clientVersion) {
            return $this->buildUpgradeRequiredResponse($app, null, null, $policyData);
        }

        $clientBuild = $clientBuildHeader !== null ? (int) $clientBuildHeader : 0;

        // Semantic version & build comparison
        $isOutdated = AppVersionComparator::isLessThan($clientVersion, $clientBuild, $minVersion, $minBuild);

        if ($isOutdated) {
            return $this->buildUpgradeRequiredResponse($app, $clientVersion, $clientBuild, $policyData);
        }

        return $next($request);
    }

    /**
     * Resolve the target app (customer or partner) from header or route.
     */
    protected function resolveAppIdentifier(Request $request): ?string
    {
        $headerApp = $request->header('X-App-Id') ?? $request->header('x-app-id');
        if ($headerApp) {
            $normalized = strtolower(trim($headerApp));
            if (in_array($normalized, AppRelease::APPS, true)) {
                return $normalized;
            }
        }

        // Infer from route path
        if ($request->is('api/customer/*') || $request->is('customer/*')) {
            return AppRelease::APP_CUSTOMER;
        }

        if ($request->is('api/partner/*') || $request->is('partner/*')) {
            return AppRelease::APP_PARTNER;
        }

        return null;
    }

    /**
     * Retrieve cached policy for app.
     */
    protected function getPolicyData(string $app): ?array
    {
        return Cache::remember("app_version_policy_{$app}", 300, function () use ($app) {
            $policy = AppUpdatePolicy::with(['latestRelease', 'minimumRelease'])
                ->where('app', $app)
                ->first();

            if (! $policy) {
                return [
                    'app' => $app,
                    'has_policy' => false,
                    'is_enforced' => false,
                    'enforce_at' => null,
                    'update_mode' => 'optional',
                    'message' => null,
                    'latest' => null,
                    'minimum' => null,
                    'store_urls' => ['android' => null, 'ios' => null],
                ];
            }

            return [
                'app' => $app,
                'has_policy' => true,
                'is_enforced' => (bool) $policy->is_enforced,
                'enforce_at' => $policy->enforce_at?->toIso8601String(),
                'update_mode' => $policy->update_mode,
                'message' => $policy->update_message,
                'latest' => $policy->latestRelease ? [
                    'id' => $policy->latestRelease->id,
                    'version' => $policy->latestRelease->version,
                    'build_number' => $policy->latestRelease->build_number,
                    'released_at' => $policy->latestRelease->released_at?->toIso8601String(),
                    'release_notes' => $policy->latestRelease->release_notes,
                ] : null,
                'minimum' => $policy->minimumRelease ? [
                    'id' => $policy->minimumRelease->id,
                    'version' => $policy->minimumRelease->version,
                    'build_number' => $policy->minimumRelease->build_number,
                ] : null,
                'store_urls' => [
                    'android' => $policy->resolveAndroidStoreUrl(),
                    'ios' => $policy->resolveIosStoreUrl(),
                ],
            ];
        });
    }

    /**
     * Construct 426 Upgrade Required JSON response.
     */
    protected function buildUpgradeRequiredResponse(
        string $app,
        ?string $clientVersion,
        ?int $clientBuild,
        array $policyData
    ): Response {
        $minRelease = $policyData['minimum'] ?? [];
        $latestRelease = $policyData['latest'] ?? [];
        $minVersion = $minRelease['version'] ?? 'unknown';

        $customMessage = $policyData['message'] ?? null;
        $message = $customMessage
            ?: "A newer version of the " . ucfirst($app) . " App is required. Please update to version {$minVersion} or higher to continue.";

        return response()->json([
            'success' => false,
            'message' => $message,
            'update_required' => true,
            'app' => $app,
            'current_version' => $clientVersion,
            'current_build' => $clientBuild,
            'minimum_version' => $minRelease['version'] ?? null,
            'minimum_build' => $minRelease['build_number'] ?? null,
            'latest_version' => $latestRelease['version'] ?? null,
            'latest_build' => $latestRelease['build_number'] ?? null,
            'update_mode' => $policyData['update_mode'] ?? 'mandatory',
            'update_message' => $customMessage,
            'store_urls' => $policyData['store_urls'] ?? [
                'android' => null,
                'ios' => null,
            ],
        ], 426, [
            'X-Upgrade-Required' => 'true',
        ]);
    }
}
