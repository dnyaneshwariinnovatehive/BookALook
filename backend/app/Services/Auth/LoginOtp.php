<?php

namespace App\Services\Auth;

use Illuminate\Support\Facades\Cache;

/**
 * Checks a sign-in code against the one sent to that phone — and only that one.
 *
 * There is no code that works for every number. When WhatsApp OTP is off the
 * send step stores the demo code for the phone, so demos still work; when it is
 * on, only the code that went out on WhatsApp does.
 *
 * Store reviewers get a fixed code, but only for the exact numbers listed in
 * OTP_REVIEW_PHONES. Both settings empty means no such login exists.
 */
class LoginOtp
{
    /** Wrong guesses before the code is thrown away and a new one is needed. */
    public const MAX_ATTEMPTS = 5;

    /** Whether this phone is one of the store-review logins. */
    public function isReviewPhone(?string $phone): bool
    {
        if ($this->reviewCode() === null) {
            return false;
        }

        $phone = $this->digits($phone);

        foreach ((array) config('services.otp.review_phones', []) as $listed) {
            if ($phone !== '' && $phone === $this->digits($listed)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Whether $otp is the code for this phone. A wrong guess counts towards
     * MAX_ATTEMPTS; the last one discards the code.
     */
    public function check(string $cacheKey, ?string $phone, ?string $otp): bool
    {
        $otp = trim((string) $otp);

        if ($this->isReviewPhone($phone)) {
            return hash_equals($this->reviewCode(), $otp);
        }

        $expected = Cache::get($cacheKey);
        if ($expected === null || $otp === '') {
            return false;
        }

        if (hash_equals((string) $expected, $otp)) {
            Cache::forget($this->attemptsKey($cacheKey));
            return true;
        }

        $attempts = (int) Cache::get($this->attemptsKey($cacheKey), 0) + 1;
        if ($attempts >= self::MAX_ATTEMPTS) {
            Cache::forget($cacheKey);
            Cache::forget($this->attemptsKey($cacheKey));
        } else {
            Cache::put($this->attemptsKey($cacheKey), $attempts, now()->addMinutes(10));
        }

        return false;
    }

    /** A new code was sent: earlier wrong guesses no longer count. */
    public function resetAttempts(string $cacheKey): void
    {
        Cache::forget($this->attemptsKey($cacheKey));
    }

    private function reviewCode(): ?string
    {
        $code = trim((string) config('services.otp.review_code', ''));

        // Too short to be a code is treated as not set, never as "any code".
        return strlen($code) >= 6 ? $code : null;
    }

    /** Digits only, without the India country code, so +91 98… and 98… match. */
    private function digits(?string $phone): string
    {
        $digits = preg_replace('/\D/', '', (string) $phone);

        return strlen($digits) === 12 && str_starts_with($digits, '91') ? substr($digits, 2) : $digits;
    }

    private function attemptsKey(string $cacheKey): string
    {
        return $cacheKey . '_attempts';
    }
}
