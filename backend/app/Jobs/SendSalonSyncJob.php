<?php

namespace App\Jobs;

use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Models\UserDevice;
use App\Services\Notifications\PushGateway;
use App\Services\Notifications\PushPayload;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * Tell every partner-app phone at a salon that its bookings just changed.
 *
 * A silent push: nothing appears on screen, the open app simply refreshes the
 * list it is showing. That is what makes a booking made in the customer app
 * show up on the salon's screen within a second or two instead of at the next
 * poll. The app still polls, so a push that never arrives costs only a few
 * seconds.
 */
class SendSalonSyncJob implements ShouldQueue
{
    use Dispatchable;
    use InteractsWithQueue;
    use Queueable;

    public int $tries = 1;

    public function __construct(
        public string $salonId,
        public ?string $appointmentId = null,
    ) {
    }

    public function handle(PushGateway $gateway): void
    {
        $salon = Salon::find($this->salonId);

        if (! $salon) {
            return;
        }

        $userIds = ServiceProvider::where('salon_id', $salon->id)
            ->where('is_active', true)
            ->pluck('user_id')
            ->push($salon->admin_id)
            ->filter()
            ->unique()
            ->values();

        $devices = UserDevice::whereIn('user_id', $userIds)
            ->where('app_type', UserDevice::APP_TYPE_PARTNER)
            ->where('is_active', true)
            ->whereNotNull('push_token')
            ->get();

        if ($devices->isEmpty()) {
            return;
        }

        try {
            $gateway->send($devices, new PushPayload(
                notificationId: 'sync-' . Str::uuid(),
                type: 'salon_sync',
                title: '',
                message: '',
                appointmentId: $this->appointmentId,
                salonId: $salon->id,
                silent: true,
            ));
        } catch (\Throwable $e) {
            // Only a refresh nudge; the app's own polling catches up.
            Log::info('Salon sync push failed', ['salon_id' => $salon->id, 'error' => $e->getMessage()]);
        }
    }
}
