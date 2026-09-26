<?php

namespace App\Services\Notifications;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;

/**
 * Turns the service account into a short-lived Google access token.
 *
 * FCM is the only provider in the system that needs one, so rather than take on
 * a Firebase SDK — and the transitive OAuth, Guzzle and gRPC tree that comes
 * with it — the assertion is a JWT signed with ext-openssl, which PHP already
 * has. The whole exchange is one POST, and the token is cached for most of its
 * life so a burst of notifications signs once rather than once each.
 *
 * Nothing about the key or the token is ever logged. Only the outcome.
 */
class FcmAccessTokenProvider
{
    private const CACHE_KEY = 'push.fcm.access_token';

    private const TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';

    /**
     * Google rejects a token with less than about a minute left, so a token is
     * treated as spent a little early rather than being used once and bounced.
     */
    private const EXPIRY_MARGIN_SECONDS = 60;

    public function __construct(private FcmCredentials $credentials)
    {
    }

    public function token(): string
    {
        $cached = Cache::get(self::CACHE_KEY);

        if (is_string($cached) && $cached !== '') {
            return $cached;
        }

        $accessToken = $this->requestToken();

        // Google's own access tokens last an hour. Caching for 50 minutes keeps
        // the safety margin without a second request on every single push.
        Cache::put(self::CACHE_KEY, $accessToken, now()->addMinutes(50));

        return $accessToken;
    }

    /**
     * Throw the cached token away. Called when FCM answers 401, which means the
     * token was revoked or the key rotated underneath us rather than that the
     * clock ran out.
     */
    public function forget(): void
    {
        Cache::forget(self::CACHE_KEY);
    }

    private function requestToken(): string
    {
        $response = Http::asForm()
            ->withOptions(['verify' => true])
            ->timeout(15)
            ->post(self::TOKEN_ENDPOINT, [
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion' => $this->assertion(),
            ]);

        if (! $response->successful()) {
            // The error body is echoed by Google verbatim and can quote the
            // subject and audience of the assertion. Log the shape, not the
            // body.
            Log::error('Could not obtain a Firebase access token', [
                'status' => $response->status(),
                'error' => $response->json('error'),
                'project_id' => $this->credentials->projectId,
            ]);

            throw new RuntimeException(
                'Firebase rejected the service-account assertion (HTTP '.$response->status().'). '
                .'Check FCM_PROJECT_ID, FCM_CLIENT_EMAIL and that the key has not been revoked.'
            );
        }

        $token = $response->json('access_token');

        if (! is_string($token) || $token === '') {
            throw new RuntimeException('Firebase returned no access token for the service account.');
        }

        return $token;
    }

    /**
     * A signed JWT-bearer assertion, built by hand.
     *
     * The shape is fixed by Google's OAuth token endpoint: a base64url header, a
     * base64url claim set, and an RS256 signature over the two joined by a dot.
     */
    private function assertion(): string
    {
        $issuedAt = time();

        $header = $this->base64UrlEncode((string) json_encode([
            'alg' => 'RS256',
            'typ' => 'JWT',
        ]));

        $claims = $this->base64UrlEncode((string) json_encode([
            'iss' => $this->credentials->clientEmail,
            'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
            'aud' => self::TOKEN_ENDPOINT,
            'iat' => $issuedAt,
            'exp' => $issuedAt + 3600,
        ]));

        $signingInput = $header.'.'.$claims;

        $signed = openssl_sign(
            $signingInput,
            $signature,
            $this->credentials->privateKey,
            OPENSSL_ALGO_SHA256
        );

        if ($signed === false) {
            throw new RuntimeException(
                'Could not sign the Firebase assertion. FCM_PRIVATE_KEY is almost certainly not a '
                .'usable PEM private key — check that its newlines survived being pasted into .env.'
            );
        }

        return $signingInput.'.'.$this->base64UrlEncode($signature);
    }

    private function base64UrlEncode(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }
}
