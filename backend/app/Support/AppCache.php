<?php

namespace App\Support;

use Closure;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Disposable caching for slow-changing, shared, non-financial reads.
 *
 * Keys follow "{module}:{resource}:{identifier}"; the Redis connection adds
 * "bookalook:{environment}:", e.g. bookalook:production:app:version:customer.
 *
 * The cache is never the source of truth:
 *  - read fails (Redis down)  -> the loader runs, i.e. PostgreSQL answers;
 *  - write fails              -> the loader's result is returned anyway;
 *  - inside a DB transaction  -> the write waits for the commit and is
 *                                dropped on rollback, so rows that never
 *                                committed are never cached;
 *  - invalidation             -> after the surrounding transaction commits; a
 *                                failure is logged at error level
 *                                ("app_cache.invalidate_failed") and the TTL
 *                                bounds how long a stale value can live.
 *
 * Only connection-level cache errors are caught (see isCacheFailure); any
 * other exception — including one thrown by the loader — propagates as usual.
 *
 * Never use this for OTPs, rate limits, locks or anything security-related:
 * those live on the `state` store and fail closed.
 */
class AppCache
{
    /** Wraps cached values so a cached null is told apart from a miss. */
    private const BOX = '__v';

    public static function remember(string $key, int $seconds, Closure $loader): mixed
    {
        try {
            $boxed = Cache::get($key);
        } catch (Throwable $e) {
            if (! self::isCacheFailure($e)) {
                throw $e;
            }
            self::report('app_cache.read_failed', $key, $e);

            return $loader();
        }

        if (is_array($boxed) && array_key_exists(self::BOX, $boxed)) {
            return $boxed[self::BOX];
        }

        $value = $loader();

        // Runs now outside a transaction; otherwise only once it commits.
        DB::afterCommit(static function () use ($key, $value, $seconds) {
            try {
                Cache::put($key, [self::BOX => $value], $seconds);
            } catch (Throwable $e) {
                if (! self::isCacheFailure($e)) {
                    throw $e;
                }
                self::report('app_cache.write_failed', $key, $e);
            }
        });

        return $value;
    }

    /** Drop keys once the current transaction (if any) has committed. */
    public static function forget(string ...$keys): void
    {
        $run = static function () use ($keys) {
            foreach ($keys as $key) {
                try {
                    Cache::forget($key);
                } catch (Throwable $e) {
                    if (! self::isCacheFailure($e)) {
                        throw $e;
                    }
                    self::report('app_cache.invalidate_failed', $key, $e, 'error');
                }
            }
        };

        DB::afterCommit($run);
    }

    /**
     * A cache-store connection problem, as opposed to an application error.
     * PhpRedis throws \RedisException (connect refused, timeout, auth, OOM).
     */
    private static function isCacheFailure(Throwable $e): bool
    {
        return $e instanceof \RedisException
            || (class_exists(\Predis\Connection\ConnectionException::class) && $e instanceof \Predis\Connection\ConnectionException);
    }

    private static function report(string $event, string $key, Throwable $e, string $level = 'warning'): void
    {
        // The key is safe to log (no secrets in cache keys); the value never is.
        Log::log($level, $event, ['key' => $key, 'error' => $e->getMessage()]);
    }
}
