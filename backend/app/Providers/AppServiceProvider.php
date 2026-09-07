<?php

namespace App\Providers;

use App\Services\Notifications\LogWhatsAppGateway;
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
        // Until a WhatsApp Business account is connected the log driver is the
        // only implementation; add the real one here keyed on the same config.
        $this->app->bind(WhatsAppGateway::class, function () {
            return match (config('services.whatsapp.driver')) {
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
        //
    }
}
