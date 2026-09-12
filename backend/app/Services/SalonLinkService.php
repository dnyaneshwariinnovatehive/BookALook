<?php

namespace App\Services;

use App\Models\PlatformPolicySetting;
use App\Models\Salon;

/**
 * The address a salon's QR code points at, and where that address sends people.
 *
 * A printed QR is the least forgiving thing the platform produces. It goes on a
 * wall, it gets laminated, and nobody reprints it because a URL changed — so
 * the link it carries is built in exactly one place, from a base address
 * SuperAdmin can move without invalidating a single poster.
 *
 * The code always carries a plain https link, never a custom scheme. Google
 * Lens and the scanner built into a phone camera will open http and https and
 * quietly ignore anything else, and most people scanning a poster in a salon
 * window are using one of those rather than the app.
 */
class SalonLinkService
{
    /**
     * The scheme the customer app registers.
     *
     * Baked into the app binary, so it is a constant rather than a setting —
     * changing it here without shipping a new build would break every link.
     */
    public const APP_SCHEME = 'bookalook';

    /** The Android package, needed to build an intent:// fallback for Chrome. */
    public const ANDROID_PACKAGE = 'com.bookalook.customer_app';

    /**
     * Where a scan lands: a real web page that works with no app installed.
     */
    public function publicUrl(Salon $salon): string
    {
        return $this->baseUrl() . '/s/' . $salon->slug;
    }

    /**
     * What the landing page asks the phone to open.
     *
     * The id rather than the slug, because the app's salon screen is addressed
     * by id and resolving a slug would mean a round trip before anything is
     * drawn.
     */
    public function deepLink(Salon $salon): string
    {
        return self::APP_SCHEME . '://salon/' . $salon->id;
    }

    /**
     * The Android intent:// form, which Chrome honours when a bare custom
     * scheme is silently swallowed.
     */
    public function androidIntentLink(Salon $salon, ?string $fallbackUrl = null): string
    {
        $fallback = $fallbackUrl ?? $this->storeLink('android') ?? $this->publicUrl($salon);

        return sprintf(
            'intent://salon/%s#Intent;scheme=%s;package=%s;S.browser_fallback_url=%s;end',
            $salon->id,
            self::APP_SCHEME,
            self::ANDROID_PACKAGE,
            rawurlencode($fallback)
        );
    }

    /**
     * Everything the landing page needs to decide what to offer.
     *
     * @return array<string, mixed>
     */
    public function appLinks(): array
    {
        $android = $this->storeLink('android');
        $ios = $this->storeLink('ios');
        $apk = $this->trimmed('android_apk_url');

        return [
            'android_app_url' => $android,
            'ios_app_url' => $ios,
            'android_apk_url' => $apk,
            // The page hides a button it has no link for. Sending somebody to
            // a store page that does not exist yet is worse than not offering.
            'has_android' => $android !== null || $apk !== null,
            'has_ios' => $ios !== null,
            'app_scheme' => self::APP_SCHEME,
            'android_package' => self::ANDROID_PACKAGE,
        ];
    }

    /** The store listing for a platform, or null while it is not live yet. */
    public function storeLink(string $platform): ?string
    {
        return $this->trimmed($platform === 'ios' ? 'ios_app_url' : 'android_app_url');
    }

    /**
     * The public site address, without a trailing slash so callers can join
     * paths without thinking about it.
     */
    public function baseUrl(): string
    {
        $configured = $this->trimmed('public_web_url');

        return rtrim($configured ?? 'http://localhost:3000', '/');
    }

    private function trimmed(string $key): ?string
    {
        $value = trim((string) PlatformPolicySetting::value($key, ''));

        return $value === '' ? null : $value;
    }
}
