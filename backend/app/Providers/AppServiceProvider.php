<?php

namespace App\Providers;

use Illuminate\Support\Facades\DB;

use App\Services\Notifications\LogWhatsAppGateway;
use App\Services\Notifications\MetaCloudWhatsAppGateway;
use App\Services\Notifications\WhatsAppGateway;
use App\Services\Payments\DemoPaymentGateway;
use App\Services\Payments\PaymentGateway;
use App\Services\Payments\RazorpayGateway;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        // Meta's Cloud API when it is configured, the log driver otherwise.
        // Falling back on missing credentials rather than throwing is
        // deliberate: a half-configured environment should queue messages for
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
                default => new LogWhatsAppGateway(),
            };
        });

        // Razorpay for appointment advances. Falls back to the demo gateway
        // whenever keys are missing, so a half-configured environment cannot
        // silently try to take real money through an unconfigured provider.
        $this->app->bind(PaymentGateway::class, function () {
            $config = config('services.razorpay');
            $hasKeys = ! empty($config['key_id']) && ! empty($config['key_secret']);

            if ($config['driver'] === 'razorpay' && $hasKeys) {
                return new RazorpayGateway(
                    $config['key_id'],
                    $config['key_secret'],
                    $config['display_name'],
                );
            }

            return new DemoPaymentGateway($config['demo_secret'], $config['display_name']);
        });
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        $this->teachSqliteToMeasureDistance();
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
