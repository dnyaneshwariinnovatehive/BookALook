<?php

namespace App\Console\Commands;

use App\Services\Auth\LoginOtp;
use App\Services\Auth\OtpStore;
use App\Support\AppCache;
use Illuminate\Console\Command;
use Illuminate\Redis\Limiters\DurationLimiter;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Str;

/**
 * Checks the two Redis (Valkey) instances the way the app uses them.
 *
 *   php artisan app:redis-selfcheck
 *
 * Writes only keys under "selfcheck:" with short TTLs and deletes them. Never
 * flushes, never prints passwords or codes. Safe to run in production.
 */
class RedisSelfCheck extends Command
{
    protected $signature = 'app:redis-selfcheck
        {--worker= : internal: consume|throttle (used by the concurrency checks)}
        {--key= : internal}
        {--code= : internal}';

    protected $description = 'Verify the cache and state Redis instances, atomic OTP use, shared rate limits and outage behaviour';

    private int $pass = 0;

    private int $fail = 0;

    public function handle(): int
    {
        if ($this->option('worker')) {
            return $this->worker();
        }

        $run = 'selfcheck:' . Str::lower(Str::random(8));

        $this->line('== Connections');
        foreach (['cache' => 6379, 'state' => 6380] as $name => $port) {
            $this->check("{$name}: PING", fn () => in_array(Redis::connection($name)->ping(), [true, '+PONG', 'PONG'], true));
            $this->check("{$name}: is the instance on port {$port}", fn () => (int) (Redis::connection($name)->info('server')['tcp_port'] ?? 0) === $port);
            // PhpRedis answers a refused command (NOPERM) with false, not an exception.
            $this->check("{$name}: app user cannot run CONFIG", fn () => $this->refused(fn () => Redis::connection($name)->config('GET', 'maxmemory')));
        }
        $this->check('cache store "redis" uses the cache connection', fn () => Cache::store('redis')->getStore()->connection()->getName() === 'cache');
        $this->check('cache store "redis" locks on the state connection', fn () => Cache::store('redis')->getStore()->lockConnection()->getName() === 'state');
        $this->check('store "state" uses the state connection', fn () => Cache::store('state')->getStore()->connection()->getName() === 'state');
        $this->check('rate limiter store is "state"', fn () => config('cache.limiter') === 'state');
        $this->info('  key prefix: ' . config('database.redis.options.prefix') . '…');

        $this->line('== Read / write / delete / TTL / locks');
        foreach (['redis', 'state'] as $store) {
            $c = Cache::store($store);
            $this->check("{$store}: put/get", function () use ($c, $run) {
                $c->put("{$run}:rw", 'v', 60);

                return $c->get("{$run}:rw") === 'v';
            });
            $this->check("{$store}: forget", function () use ($c, $run) {
                $c->forget("{$run}:rw");

                return $c->get("{$run}:rw") === null;
            });
            $this->check("{$store}: expires after its TTL", function () use ($c, $run) {
                $c->put("{$run}:ttl", 'v', 1);
                usleep(2_200_000);

                return $c->get("{$run}:ttl") === null;
            });
            $this->check("{$store}: a lock is exclusive and releases", function () use ($c, $run) {
                $a = $c->lock("{$run}:lock", 10);
                $b = $c->lock("{$run}:lock", 10);
                $ok = $a->get() && ! $b->get();
                $a->release();

                return $ok && $b->get() && $b->release();
            });
        }

        $this->line('== OTP on the state instance');
        $otps = app(OtpStore::class);
        $this->check('right code works once, then never again', function () use ($otps, $run) {
            $otps->issue("{$run}:otp", '481516', 1);

            return $otps->consume("{$run}:otp", '481516', 5, 1) === OtpStore::OK
                && $otps->consume("{$run}:otp", '481516', 5, 1) === OtpStore::EXPIRED;
        });
        $this->check('code for one key is refused for another', function () use ($otps, $run) {
            $otps->issue("{$run}:otp:a", '111222', 1);
            $r = $otps->consume("{$run}:otp:b", '111222', 5, 1);
            $otps->forget("{$run}:otp:a");

            return $r === OtpStore::EXPIRED;
        });
        $this->check('5 wrong guesses burn the code', function () use ($otps, $run) {
            $otps->issue("{$run}:otp:w", '999000', 1);
            $results = [];
            foreach (range(1, 5) as $_) {
                $results[] = $otps->consume("{$run}:otp:w", '000000', 5, 1);
            }

            return end($results) === OtpStore::BURNED
                && $otps->consume("{$run}:otp:w", '999000', 5, 1) === OtpStore::EXPIRED;
        });
        $this->check('8 processes racing with the right code: exactly 1 succeeds', function () use ($otps, $run) {
            $otps->issue("{$run}:otp:race", '424242', 1);
            $ok = collect($this->parallel(8, ['--worker' => 'consume', '--key' => "{$run}:otp:race", '--code' => '424242']))
                ->filter(fn ($out) => trim($out) === OtpStore::OK)->count();
            $this->info("    successes: {$ok}");

            return $ok === 1;
        });

        $this->line('== Rate limits on the state instance (atomic, shared by all workers)');
        $this->check('10 processes against a limit of 3: exactly 3 allowed', function () use ($run) {
            $allowed = collect($this->parallel(10, ['--worker' => 'throttle', '--key' => "{$run}:limit"]))
                ->filter(fn ($out) => trim($out) === '1')->count();
            $this->info("    allowed: {$allowed}");

            return $allowed === 3;
        });
        $this->check('the window expires', function () use ($run) {
            sleep(3);

            return (new DurationLimiter(Redis::connection('state'), "{$run}:limit", 3, 2))->acquire();
        });
        $this->check('throttle middleware counts on Redis', fn () => app('router')->getMiddleware()['throttle'] === \App\Http\Middleware\ThrottleRequestsWithStateRedis::class);

        $this->line('== Outages (simulated in this process only, by pointing at a closed port)');
        $this->check('cache down: AppCache returns the database value', function () use ($run) {
            return $this->withConnectionDown('cache', 'redis', fn () => $this->throws(fn () => Cache::store('redis')->get('x'))
                && AppCache::remember("{$run}:down", 60, fn () => 'from-postgres') === 'from-postgres');
        });
        $this->check('state down: OTP check fails closed (throws)', function () {
            return $this->withConnectionDown('state', 'state', fn () => $this->throws(
                fn () => app(LoginOtp::class)->check(LoginOtp::CUSTOMER, '9000000000', '123456')
            ));
        });
        $this->check('state down: rate limit fails closed (throws)', function () use ($run) {
            return $this->withConnectionDown('state', 'state', fn () => $this->throws(
                fn () => (new DurationLimiter(Redis::connection('state'), "{$run}:x", 3, 10))->acquire()
            ));
        });

        // Clean up what this run wrote (all of it has a TTL of a minute or less anyway).
        try {
            foreach (['cache', 'state'] as $name) {
                $conn = Redis::connection($name);
                $prefix = (string) config('database.redis.options.prefix');
                foreach (['', 'state:'] as $storePrefix) {
                    foreach ($conn->keys("{$storePrefix}{$run}*") ?: [] as $key) {
                        $conn->del(Str::after($key, $prefix));
                    }
                }
            }
        } catch (\Throwable $e) {
            $this->warn('  cleanup skipped: ' . class_basename($e));
        }

        $this->newLine();
        $this->line("RESULT: {$this->pass} passed, {$this->fail} failed");
        foreach (['cache', 'state'] as $name) {
            $mem = Redis::connection($name)->info('memory');
            $stats = Redis::connection($name)->info('stats');
            $this->line(sprintf('  %s: used %s, evicted_keys %s, hits %s, misses %s', $name,
                $mem['used_memory_human'] ?? '?', $stats['evicted_keys'] ?? '?', $stats['keyspace_hits'] ?? '?', $stats['keyspace_misses'] ?? '?'));
        }

        return $this->fail === 0 ? self::SUCCESS : self::FAILURE;
    }

    /** One step of a concurrency check, run in its own process. */
    private function worker(): int
    {
        $key = (string) $this->option('key');

        if ($this->option('worker') === 'consume') {
            $this->output->write(app(OtpStore::class)->consume($key, (string) $this->option('code'), 5, 1));
        } else {
            $this->output->write((new DurationLimiter(Redis::connection('state'), $key, 3, 2))->acquire() ? '1' : '0');
        }

        return self::SUCCESS;
    }

    /** Start $n copies of this command at once; return each one's output. */
    private function parallel(int $n, array $options): array
    {
        $args = [PHP_BINARY, base_path('artisan'), 'app:redis-selfcheck'];
        foreach ($options as $k => $v) {
            $args[] = "{$k}={$v}";
        }

        $procs = [];
        foreach (range(1, $n) as $i) {
            $procs[$i] = proc_open($args, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes[$i], base_path());
        }
        $out = [];
        foreach ($procs as $i => $proc) {
            $out[$i] = stream_get_contents($pipes[$i][1]);
            fclose($pipes[$i][1]);
            fclose($pipes[$i][2]);
            proc_close($proc);
        }

        return $out;
    }

    /**
     * Run $test with $connection pointing at a closed port. Laravel's Redis
     * manager copies its config when built, so a fresh manager is swapped in
     * (changing config() alone would not break anything). Fails the check if
     * the outage did not take effect.
     */
    private function withConnectionDown(string $connection, string $store, \Closure $test): bool
    {
        $original = app('redis');
        $config = config('database.redis');
        $config[$connection]['port'] = 1;

        app()->instance('redis', new \Illuminate\Redis\RedisManager(app(), $config['client'] ?? 'phpredis', $config));
        Redis::clearResolvedInstance('redis');
        Cache::forgetDriver($store);
        $default = Cache::getDefaultDriver();
        Cache::setDefaultDriver($store);

        try {
            if (! $this->throws(fn () => Redis::connection($connection)->ping())) {
                throw new \RuntimeException("could not simulate an outage of {$connection}");
            }

            return (bool) $test();
        } finally {
            Cache::setDefaultDriver($default);
            app()->instance('redis', $original);
            Redis::clearResolvedInstance('redis');
            Cache::forgetDriver($store);
        }
    }

    private function refused(\Closure $run): bool
    {
        try {
            return $run() === false;
        } catch (\Throwable) {
            return true;
        }
    }

    private function throws(\Closure $run): bool
    {
        try {
            $run();

            return false;
        } catch (\Throwable) {
            return true;
        }
    }

    private function check(string $name, \Closure $test): void
    {
        try {
            $ok = (bool) $test();
            $error = '';
        } catch (\Throwable $e) {
            $ok = false;
            $error = ' — ' . class_basename($e) . ': ' . Str::limit($e->getMessage(), 120);
        }
        $ok ? $this->pass++ : $this->fail++;
        $this->line(($ok ? '  PASS  ' : '  FAIL  ') . $name . $error);
    }
}
