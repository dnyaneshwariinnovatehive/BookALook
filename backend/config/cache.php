<?php

use Illuminate\Support\Str;

return [

    /*
    |--------------------------------------------------------------------------
    | Default Cache Store
    |--------------------------------------------------------------------------
    |
    | This option controls the default cache store that will be used by the
    | framework. This connection is utilized if another isn't explicitly
    | specified when running a cache operation inside the application.
    |
    */

    'default' => env('CACHE_STORE', 'database'),

    /*
    |--------------------------------------------------------------------------
    | Cache Stores
    |--------------------------------------------------------------------------
    |
    | Here you may define all of the cache "stores" for your application as
    | well as their drivers. You may even define multiple stores for the
    | same cache driver to group types of items stored in your caches.
    |
    | Supported drivers: "array", "database", "file", "memcached",
    |                    "redis", "dynamodb", "octane", "null"
    |
    */

    'stores' => [

        'array' => [
            'driver' => 'array',
            'serialize' => false,
        ],

        'database' => [
            'driver' => 'database',
            'connection' => env('DB_CACHE_CONNECTION'),
            'table' => env('DB_CACHE_TABLE', 'cache'),
            'lock_connection' => env('DB_CACHE_LOCK_CONNECTION'),
            'lock_table' => env('DB_CACHE_LOCK_TABLE'),
        ],

        'file' => [
            'driver' => 'file',
            'path' => storage_path('framework/cache/data'),
            'lock_path' => storage_path('framework/cache/data'),
        ],

        'memcached' => [
            'driver' => 'memcached',
            'persistent_id' => env('MEMCACHED_PERSISTENT_ID'),
            'sasl' => [
                env('MEMCACHED_USERNAME'),
                env('MEMCACHED_PASSWORD'),
            ],
            'options' => [
                // Memcached::OPT_CONNECT_TIMEOUT => 2000,
            ],
            'servers' => [
                [
                    'host' => env('MEMCACHED_HOST', '127.0.0.1'),
                    'port' => env('MEMCACHED_PORT', 11211),
                    'weight' => 100,
                ],
            ],
        ],

        // Disposable application cache on the cache instance (6379). Its locks
        // (scheduler withoutOverlapping, Cache::lock) live on the state
        // instance, which never evicts, so a full cache cannot drop a lock.
        'redis' => [
            'driver' => 'redis',
            'connection' => env('REDIS_CACHE_CONNECTION', 'cache'),
            'lock_connection' => env('REDIS_CACHE_LOCK_CONNECTION', 'state'),
            // No extra prefix: keys read bookalook:{env}:{module}:{resource}:{id}.
            'prefix' => '',
        ],

        // Security state on the state instance (6380): OTP codes, attempt
        // counters, verified-phone markers. Never falls back to anything: if
        // it is unreachable, sign-in fails instead of skipping a check.
        // STATE_STORE_DRIVER: redis (normal), database (rollback: back on
        // PostgreSQL, same behaviour), array (tests, no Redis).
        'state' => match (env('STATE_STORE_DRIVER', 'redis')) {
            'array' => ['driver' => 'array', 'serialize' => true],
            'database' => [
                'driver' => 'database',
                'connection' => env('DB_CACHE_CONNECTION'),
                'table' => env('DB_CACHE_TABLE', 'cache'),
                'lock_connection' => env('DB_CACHE_LOCK_CONNECTION'),
                'lock_table' => env('DB_CACHE_LOCK_TABLE'),
            ],
            default => [
                'driver' => 'redis',
                'connection' => 'state',
                'lock_connection' => 'state',
                'prefix' => 'state:',
            ],
        },

        'dynamodb' => [
            'driver' => 'dynamodb',
            'key' => env('AWS_ACCESS_KEY_ID'),
            'secret' => env('AWS_SECRET_ACCESS_KEY'),
            'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
            'table' => env('DYNAMODB_CACHE_TABLE', 'cache'),
            'endpoint' => env('DYNAMODB_ENDPOINT'),
        ],

        'octane' => [
            'driver' => 'octane',
        ],

    ],

    /*
    |--------------------------------------------------------------------------
    | Cache Key Prefix
    |--------------------------------------------------------------------------
    |
    | When utilizing the APC, database, memcached, Redis, and DynamoDB cache
    | stores, there might be other applications using the same cache. For
    | that reason, you may prefix every cache key to avoid collisions.
    |
    */

    'prefix' => env('CACHE_PREFIX', Str::slug(env('APP_NAME', 'laravel'), '_').'_cache_'),

    /*
    | Rate-limit counters. `state` keeps them on the state instance, shared by
    | every PHP-FPM worker; when that store is Redis the throttle middleware
    | counts with one atomic Lua script per limit (see AppServiceProvider).
    */
    'limiter' => env('CACHE_LIMITER_STORE', 'state'),

];
