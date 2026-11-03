<?php

use Illuminate\Support\Str;

return [

    /*
    |--------------------------------------------------------------------------
    | Default Database Connection Name
    |--------------------------------------------------------------------------
    |
    | Here you may specify which of the database connections below you wish
    | to use as your default connection for database operations. This is
    | the connection which will be utilized unless another connection
    | is explicitly specified when you execute a query / statement.
    |
    */

    'default' => env('DB_CONNECTION', 'sqlite'),

    /*
    |--------------------------------------------------------------------------
    | Database Connections
    |--------------------------------------------------------------------------
    |
    | Below are all of the database connections defined for your application.
    | An example configuration is provided for each database system which
    | is supported by Laravel. You're free to add / remove connections.
    |
    */

    'connections' => [

        'sqlite' => [
            'driver' => 'sqlite',
            'url' => env('DB_URL'),
            'database' => env('DB_DATABASE', database_path('database.sqlite')),
            'prefix' => '',
            'foreign_key_constraints' => env('DB_FOREIGN_KEYS', true),
            'busy_timeout' => null,
            'journal_mode' => null,
            'synchronous' => null,
        ],

        'sqlite_old' => [
            'driver' => 'sqlite',
            'database' => database_path('database.sqlite'),
            'prefix' => '',
            'foreign_key_constraints' => false,
        ],

        'mysql' => [
            'driver' => 'mysql',
            'url' => env('DB_URL'),
            'host' => env('DB_HOST', '127.0.0.1'),
            'port' => env('DB_PORT', '3306'),
            'database' => env('DB_DATABASE', 'laravel'),
            'username' => env('DB_USERNAME', 'root'),
            'password' => env('DB_PASSWORD', ''),
            'unix_socket' => env('DB_SOCKET', ''),
            'charset' => env('DB_CHARSET', 'utf8mb4'),
            'collation' => env('DB_COLLATION', 'utf8mb4_unicode_ci'),
            'prefix' => '',
            'prefix_indexes' => true,
            'strict' => true,
            'engine' => null,
            'options' => extension_loaded('pdo_mysql') ? array_filter([
                PDO::MYSQL_ATTR_SSL_CA => env('MYSQL_ATTR_SSL_CA'),
            ]) : [],
        ],

        'mariadb' => [
            'driver' => 'mariadb',
            'url' => env('DB_URL'),
            'host' => env('DB_HOST', '127.0.0.1'),
            'port' => env('DB_PORT', '3306'),
            'database' => env('DB_DATABASE', 'laravel'),
            'username' => env('DB_USERNAME', 'root'),
            'password' => env('DB_PASSWORD', ''),
            'unix_socket' => env('DB_SOCKET', ''),
            'charset' => env('DB_CHARSET', 'utf8mb4'),
            'collation' => env('DB_COLLATION', 'utf8mb4_unicode_ci'),
            'prefix' => '',
            'prefix_indexes' => true,
            'strict' => true,
            'engine' => null,
            'options' => extension_loaded('pdo_mysql') ? array_filter([
                PDO::MYSQL_ATTR_SSL_CA => env('MYSQL_ATTR_SSL_CA'),
            ]) : [],
        ],

        'pgsql' => [
            'driver' => 'pgsql',
            'url' => env('DB_URL'),
            'host' => env('DB_HOST', '127.0.0.1'),
            'port' => env('DB_PORT', '5432'),
            'database' => env('DB_DATABASE', 'laravel'),
            'username' => env('DB_USERNAME', 'root'),
            'password' => env('DB_PASSWORD', ''),
            'charset' => env('DB_CHARSET', 'utf8'),
            'prefix' => '',
            'prefix_indexes' => true,
            'search_path' => 'public',
            'sslmode' => 'prefer',
        ],

        'sqlsrv' => [
            'driver' => 'sqlsrv',
            'url' => env('DB_URL'),
            'host' => env('DB_HOST', 'localhost'),
            'port' => env('DB_PORT', '1433'),
            'database' => env('DB_DATABASE', 'laravel'),
            'username' => env('DB_USERNAME', 'root'),
            'password' => env('DB_PASSWORD', ''),
            'charset' => env('DB_CHARSET', 'utf8'),
            'prefix' => '',
            'prefix_indexes' => true,
            // 'encrypt' => env('DB_ENCRYPT', 'yes'),
            // 'trust_server_certificate' => env('DB_TRUST_SERVER_CERTIFICATE', 'false'),
        ],

    ],

    /*
    |--------------------------------------------------------------------------
    | Migration Repository Table
    |--------------------------------------------------------------------------
    |
    | This table keeps track of all the migrations that have already run for
    | your application. Using this information, we can determine which of
    | the migrations on disk haven't actually been run on the database.
    |
    */

    'migrations' => [
        'table' => 'migrations',
        'update_date_on_publish' => true,
    ],

    /*
    |--------------------------------------------------------------------------
    | Redis Databases
    |--------------------------------------------------------------------------
    |
    | Redis is an open source, fast, and advanced key-value store that also
    | provides a richer body of commands than a typical key-value system
    | such as Memcached. You may define your connection settings here.
    |
    */

    'redis' => [

        'client' => env('REDIS_CLIENT', 'phpredis'),

        // Every key starts "bookalook:{environment}:", so a staging app could
        // never read or clear production keys even on a shared instance.
        'options' => [
            'cluster' => env('REDIS_CLUSTER', 'redis'),
            'prefix' => env('REDIS_PREFIX', 'bookalook:'.env('APP_ENV', 'production').':'),
        ],

        // Two separate Redis (Valkey) instances on the VPS — see deploy/redis.
        //
        // cache (6379): disposable. allkeys-lru, no persistence. Anything here
        //   may vanish at any time; PostgreSQL is always the source.
        // state (6380): must not be lost or evicted. noeviction, AOF + RDB.
        //   OTP codes, rate-limit counters, locks; later (Phase 4) queues.
        //
        // `default` is the state instance: Laravel's locks and the Redis rate
        // limiter use it unless told otherwise.

        'default' => [
            'host' => env('REDIS_STATE_HOST', '127.0.0.1'),
            'username' => env('REDIS_STATE_USERNAME'),
            'password' => env('REDIS_STATE_PASSWORD'),
            'port' => env('REDIS_STATE_PORT', '6380'),
            'database' => env('REDIS_STATE_DB', '0'),
            'timeout' => (float) env('REDIS_TIMEOUT', 1.0),
            'read_timeout' => (float) env('REDIS_READ_TIMEOUT', 2.0),
        ],

        'state' => [
            'host' => env('REDIS_STATE_HOST', '127.0.0.1'),
            'username' => env('REDIS_STATE_USERNAME'),
            'password' => env('REDIS_STATE_PASSWORD'),
            'port' => env('REDIS_STATE_PORT', '6380'),
            'database' => env('REDIS_STATE_DB', '0'),
            'timeout' => (float) env('REDIS_TIMEOUT', 1.0),
            'read_timeout' => (float) env('REDIS_READ_TIMEOUT', 2.0),
        ],

        'cache' => [
            'host' => env('REDIS_CACHE_HOST', '127.0.0.1'),
            'username' => env('REDIS_CACHE_USERNAME'),
            'password' => env('REDIS_CACHE_PASSWORD'),
            'port' => env('REDIS_CACHE_PORT', '6379'),
            'database' => env('REDIS_CACHE_DB', '0'),
            // Short: a slow or missing cache must never hold up a request.
            'timeout' => (float) env('REDIS_CACHE_TIMEOUT', 0.5),
            'read_timeout' => (float) env('REDIS_CACHE_READ_TIMEOUT', 1.0),
        ],

    ],

];
