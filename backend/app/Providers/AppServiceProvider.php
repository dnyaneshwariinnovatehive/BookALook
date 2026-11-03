<?php

namespace App\Providers;

use Illuminate\Support\Facades\DB;

use App\Services\Notifications\AisensyWhatsAppGateway;
use App\Services\Notifications\FcmAccessTokenProvider;
use App\Services\Notifications\FcmCredentials;
use App\Services\Notifications\FcmPushGateway;
use App\Services\Notifications\LogPushGateway;
use App\Services\Notifications\LogWhatsAppGateway;
use App\Services\Notifications\MetaCloudWhatsAppGateway;
use App\Services\Notifications\PushGateway;
use App\Services\Notifications\WhatsAppGateway;
use App\Services\Payments\NoPaymentGateway;
use App\Services\Payments\PaymentGateway;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        // The configured WhatsApp provider, or the log driver when it is absent or
        // not configured. Falling back on missing credentials rather than throwing
        // is deliberate: a half-configured environment should queue messages for
        // inspection, not fail every booking that tries to notify someone.
        $this->app->bind(WhatsAppGateway::class, function () {
            $config = config('services.whatsapp');

            return match ($config['driver'] ?? 'log') {
                'meta_cloud' => filled($config['phone_number_id']) && filled($config['access_token'])
                    ? new MetaCloudWhatsAppGateway(
                        $config['phone_number_id'],
                        $config['access_token'],
                        $config['api_version'] ?? 'v21.0',
                    )
                    : new LogWhatsAppGateway(),
                'aisensy' => filled($config['aisensy']['api_key'] ?? null)
                    ? new AisensyWhatsAppGateway(
                        $config['aisensy']['api_key'],
                        $config['campaigns'] ?? [],
                        $config['aisensy']['base_url'] ?? 'https://backend.aisensy.com',
                        $config['aisensy']['source'] ?? 'bookalook',
                    )
                    : new LogWhatsAppGateway(),
                default => new LogWhatsAppGateway(),
            };
        });

        // Push notifications. `log` is the driver for every environment until a
        // Firebase project exists: it records what would have gone out and
        // contacts nobody, so the whole pipeline can be exercised before a single
        // customer is disturbed by a real push.
        //
        // `fcm` is the real one, and unlike the payment gateways it does NOT
        // fall back. Selecting a driver means the operator asked for a working
        // send, so a missing service account is reported loudly — by name, once,
        // at the point the driver is resolved — rather than silently downgrading
        // to a log driver that reports every delivery as `sent` and so hides the
        // misconfiguration behind a green ledger. `MissingFcmCredentials` names
        // the variables that are absent and nothing else.
        $this->app->bind(PushGateway::class, function () {
            $driver = (string) config('services.push.driver', 'log');

            if ($driver !== 'fcm') {
                return new LogPushGateway();
            }

            $credentials = FcmCredentials::fromConfig();

            return new FcmPushGateway($credentials, new FcmAccessTokenProvider($credentials));
        });

        // Online payments for appointments. None is configured: bookings are
        // confirmed without a payment step and the salon records what it is
        // paid. A future provider implements PaymentGateway and is selected
        // here by PAYMENT_DRIVER; anything unrecognised stays on `none`, so a
        // half-configured environment can never try to take real money.
        $this->app->bind(PaymentGateway::class, function () {
            $config = config('services.payments');

            return match ($config['driver'] ?? 'none') {
                default => new NoPaymentGateway($config['display_name'] ?? 'BookALook'),
            };
        });
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        $this->teachSqliteToMeasureDistance();
        $this->limitSignIns();
    }

    /**
     * Limits on the sign-in endpoints, counted per phone (or email) and per IP,
     * so codes cannot be guessed or WhatsApp sends run up. Over the limit the
     * API answers 429 with a message the apps show as is.
     */
    private function limitSignIns(): void
    {
        $phone = fn (Request $r) => preg_replace('/\D/', '', (string) $r->input('phone'));

        RateLimiter::for('otp-send', fn (Request $r) => [
            Limit::perMinute(3)->by('otp-send:phone:' . $phone($r))
                ->response(fn () => response()->json(['message' => 'Please wait a minute before asking for another code.'], 429)),
            Limit::perHour(10)->by('otp-send:phone-hour:' . $phone($r))
                ->response(fn () => response()->json(['message' => 'Too many codes asked for this number. Try again in an hour.'], 429)),
            Limit::perMinute(20)->by('otp-send:ip:' . $r->ip()),
        ]);

        RateLimiter::for('otp-verify', fn (Request $r) => [
            Limit::perMinute(10)->by('otp-verify:phone:' . $phone($r))
                ->response(fn () => response()->json(['message' => 'Too many tries. Please wait a minute.'], 429)),
            Limit::perMinute(30)->by('otp-verify:ip:' . $r->ip()),
        ]);

        RateLimiter::for('admin-login', fn (Request $r) => [
            Limit::perMinute(5)->by('admin-login:ip:' . $r->ip())
                ->response(fn () => response()->json(['success' => false, 'message' => 'Too many sign-in attempts. Please wait a minute.'], 429)),
            Limit::perHour(20)->by('admin-login:email:' . strtolower((string) $r->input('email')))
                ->response(fn () => response()->json(['success' => false, 'message' => 'Too many sign-in attempts. Try again later.'], 429)),
        ]);
    }

    /**
     * Give SQLite a haversine function, because it ships without trigonometry.
     *
     * The salon directory sorts by distance in SQL so that ordering stays
     * correct across a LIMIT — sorting a page in PHP only sorts that page.
     * MySQL and Postgres have the maths built in; the SQLite build used in
     * development has no acos, sin or cos at all, so they are registered here
     * and the same query then runs on every driver.
     */
    private function teachSqliteToMeasureDistance(): void
    {
        $connection = DB::connection();

        if ($connection->getDriverName() !== 'sqlite') {
            return;
        }

        $pdo = $connection->getPdo();

        if (! method_exists($pdo, 'sqliteCreateFunction')) {
            return;
        }

        $pdo->sqliteCreateFunction('haversine_km', function ($lat1, $lng1, $lat2, $lng2) {
            if ($lat1 === null || $lng1 === null || $lat2 === null || $lng2 === null) {
                return null;
            }

            $dLat = deg2rad((float) $lat2 - (float) $lat1);
            $dLng = deg2rad((float) $lng2 - (float) $lng1);

            $a = sin($dLat / 2) ** 2
                + cos(deg2rad((float) $lat1)) * cos(deg2rad((float) $lat2)) * sin($dLng / 2) ** 2;

            return 6371 * 2 * asin(min(1.0, sqrt($a)));
        }, 4);
    }
}
