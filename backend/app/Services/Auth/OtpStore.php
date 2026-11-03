<?php

namespace App\Services\Auth;

use Illuminate\Contracts\Cache\Repository;
use Illuminate\Support\Facades\Cache;

/**
 * One-time codes on the `state` cache store (Redis instance 2, never evicted).
 *
 * A code is stored under a key that names its purpose and its phone (and user,
 * for a phone change), so it cannot be used for another number or another
 * flow. Checking it is atomic: the compare, the delete on success and the
 * wrong-guess counter all happen while holding a lock on that key, so two
 * requests arriving together cannot both use one code.
 *
 * There is no fallback: if the state store is unreachable these methods throw
 * and the request fails. A code is never logged.
 */
class OtpStore
{
    public const OK = 'ok';
    public const WRONG = 'wrong';
    public const EXPIRED = 'expired';
    public const BURNED = 'burned';

    /** How long a request waits for another check of the same code to finish. */
    private const LOCK_WAIT_SECONDS = 3;

    public function store(): Repository
    {
        return Cache::store('state');
    }

    /** Save a new code, replacing any earlier one and its wrong guesses. */
    public function issue(string $key, string $code, int $minutes): void
    {
        $this->store()->put($key, $code, now()->addMinutes($minutes));
        $this->store()->forget($this->attemptsKey($key));
    }

    /**
     * Check $given against the stored code and use it up if it matches.
     *
     * @return string self::OK, WRONG, EXPIRED (no code), or BURNED (that was
     *                the last allowed wrong guess; the code is gone).
     */
    public function consume(string $key, string $given, int $maxAttempts, int $minutes): string
    {
        $given = trim($given);

        return $this->store()->lock($this->lockKey($key), self::LOCK_WAIT_SECONDS + 2)
            ->block(self::LOCK_WAIT_SECONDS, function () use ($key, $given, $maxAttempts, $minutes) {
                $expected = $this->store()->get($key);

                if ($expected === null) {
                    return self::EXPIRED;
                }

                if ($given !== '' && hash_equals((string) $expected, $given)) {
                    $this->store()->forget($key);
                    $this->store()->forget($this->attemptsKey($key));

                    return self::OK;
                }

                $attempts = (int) $this->store()->get($this->attemptsKey($key), 0) + 1;
                if ($attempts >= $maxAttempts) {
                    $this->store()->forget($key);
                    $this->store()->forget($this->attemptsKey($key));

                    return self::BURNED;
                }
                $this->store()->put($this->attemptsKey($key), $attempts, now()->addMinutes($minutes));

                return self::WRONG;
            });
    }

    public function forget(string $key): void
    {
        $this->store()->forget($key);
        $this->store()->forget($this->attemptsKey($key));
    }

    private function attemptsKey(string $key): string
    {
        return $key . ':attempts';
    }

    private function lockKey(string $key): string
    {
        return $key . ':lock';
    }
}
