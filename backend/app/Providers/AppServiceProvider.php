<?php

namespace App\Providers;

use App\Services\Notifications\LogWhatsAppGateway;
use App\Services\Notifications\WhatsAppGateway;
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
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        //
    }
}
