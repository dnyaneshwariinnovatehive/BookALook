<?php

namespace App\Http\Middleware;

use Illuminate\Routing\Middleware\ThrottleRequestsWithRedis;

/**
 * Laravel's Redis throttle, counting on the state instance (6380).
 *
 * Each limit is checked and counted in one atomic Lua script, so requests
 * arriving at the same moment on different PHP-FPM workers cannot slip past
 * a limit together. If the state instance is unreachable this throws and the
 * request fails — a limit is never silently skipped.
 *
 * Used for the `throttle` middleware whenever the limiter store is Redis
 * (AppServiceProvider); tests without Redis keep Laravel's cache throttle.
 */
class ThrottleRequestsWithStateRedis extends ThrottleRequestsWithRedis
{
    protected function getRedisConnection()
    {
        return $this->redis->connection('state');
    }
}
