<?php

namespace App\Services\Auth;

/**
 * Checks a sign-in code against the one sent to that phone — and only that one.
 *
 * There is no code that works for every number. A code lives 10 minutes, is
 * forgotten once used, and is thrown away after MAX_ATTEMPTS wrong guesses.
 *
 * When WhatsApp OTP is off, the send step stores the demo code instead — but
 * only outside production. In production there is no demo code at all.
 *
 * Store reviewers get a fixed code, but only for the exact numbers listed in
 * OTP_REVIEW_PHONES. Both settings empty means no such login exists.
 */
class LoginOtp
{
    /** Wrong guesses before the code is thrown away and a new one is needed. */
    public const MAX_ATTEMPTS = 5;

    /**
     * The code to store when WhatsApp OTP is off, or null when none may be
     * used (always in production).
     */
    public function demoCode(): ?string
    {
        if (app()->environment('production')) {
            return null;
        }

        $code = trim((string) config('services.otp.demo_code', ''));

        return strlen($code) === 6 ? $code : null;
    }

    /** Whether this phone is one of the store-review logins. */
    public function isReviewPhone(?string $phone): bool
    {
        if ($this->reviewCode() === null) {
            return false;
        }

        $phone = self::normalise($phone);

        foreach ((array) config('services.otp.review_phones', []) as $listed) {
            if ($phone !== '' && $phone === self::normalise($listed)) {
                return true;
            }
        }

        return false;
    }

    /** Sign-in flows. A code issued for one is never accepted by the other. */
    public const CUSTOMER = 'customer';
    public const PARTNER = 'partner';

    /** Minutes a code is valid. */
    public const MINUTES = 10;

    /** Minutes a new customer has to finish sign-up after a verified code. */
    public const VERIFIED_MINUTES = 15;

    public function __construct(private OtpStore $otps)
    {
    }

    /** Store the code sent to this phone for this flow (state store). */
    public function issue(string $flow, string $phone, string $code): void
    {
        $this->otps->issue($this->key($flow, $phone), $code, self::MINUTES);
    }

    /**
     * Whether $otp is the code sent to this phone for this flow. A match uses
     * the code up; a wrong guess counts towards MAX_ATTEMPTS, and the last one
     * discards the code. Atomic — see OtpStore.
     */
    public function check(string $flow, ?string $phone, ?string $otp): bool
    {
        $otp = trim((string) $otp);

        if ($this->isReviewPhone($phone)) {
            return hash_equals($this->reviewCode(), $otp);
        }

        return $this->otps->consume($this->key($flow, (string) $phone), $otp, self::MAX_ATTEMPTS, self::MINUTES)
            === OtpStore::OK;
    }

    /** A new customer proved the number: they may finish sign-up for a while. */
    public function markVerified(string $phone): void
    {
        $this->otps->store()->put($this->verifiedKey($phone), true, now()->addMinutes(self::VERIFIED_MINUTES));
    }

    public function isVerified(string $phone): bool
    {
        return (bool) $this->otps->store()->get($this->verifiedKey($phone));
    }

    public function forgetVerified(string $phone): void
    {
        $this->otps->store()->forget($this->verifiedKey($phone));
    }

    private function key(string $flow, string $phone): string
    {
        return "otp:{$flow}:{$phone}";
    }

    private function verifiedKey(string $phone): string
    {
        return 'otp:verified:customer:' . $phone;
    }

    private function reviewCode(): ?string
    {
        $code = trim((string) config('services.otp.review_code', ''));

        // Exactly six digits, like a real code (the apps send six). Anything
        // else is treated as not set, never as "any code".
        return preg_match('/^\d{6}$/', $code) ? $code : null;
    }

    /**
     * Digits only, without the India country code, so +91 98…, 098… and 98…
     * are the same number (rate-limit keys, review numbers).
     */
    public static function normalise(?string $phone): string
    {
        $digits = preg_replace('/\D/', '', (string) $phone);

        if (strlen($digits) === 12 && str_starts_with($digits, '91')) {
            return substr($digits, 2);
        }

        return strlen($digits) === 11 && str_starts_with($digits, '0') ? substr($digits, 1) : $digits;
    }
}
