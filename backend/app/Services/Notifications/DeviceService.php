<?php

namespace App\Services\Notifications;

use App\Models\User;
use App\Models\UserDevice;
use Illuminate\Support\Facades\DB;

/**
 * Registering, releasing and ageing out the handsets that want a push.
 *
 * Exists as a service rather than as controller code because the Customer App
 * and the Partner App need identical behaviour, and the interesting part of it —
 * handing a token over from whoever held it last — is a security decision that
 * must not be written twice.
 *
 * Two rules hold everywhere in here:
 *
 *   1. The authenticated user is the owner, always. Nothing in this class reads
 *      an owner from its arguments, so no caller can register a device onto
 *      somebody else's account.
 *   2. A token is live for exactly one user at a time. Sharing a handset, or an
 *      account being created for a number that already had the app, must not
 *      leave two accounts both believing they own it.
 */
class DeviceService
{
    /**
     * Register or refresh a device for the signed-in user.
     *
     * Idempotent on (user, token): the same install calling in twice updates the
     * existing row rather than accumulating duplicates, which is what lets the
     * app call this on every launch without thinking about it.
     *
     * @param  array{app_type: string, platform: string, push_token: string, app_version: string, device_model?: string|null, os_version?: string|null}  $data
     */
    public function register(User $user, array $data): UserDevice
    {
        return DB::transaction(function () use ($user, $data) {
            $this->releaseTokenFromPreviousOwners($user, $data['push_token']);

            // Keyed on the user as well as the token: the unique index on those
            // two columns is what stops one account registering the same
            // install twice and quietly pushing to itself.
            return UserDevice::updateOrCreate(
                ['user_id' => $user->id, 'push_token' => $data['push_token']],
                [
                    'app_type' => $data['app_type'],
                    'platform' => $data['platform'],
                    'app_version' => $data['app_version'],
                    'device_model' => $data['device_model'] ?? null,
                    'os_version' => $data['os_version'] ?? null,
                    'is_active' => true,
                    'last_active_at' => now(),
                ],
            );
        });
    }

    /**
     * Release one of this user's devices. Returns whether there was one.
     *
     * Deactivated, not deleted: the delivery ledger points at these rows, and a
     * phone that comes back should not take its delivery history down with it.
     */
    public function unregister(User $user, string $pushToken): bool
    {
        return UserDevice::query()
            ->where('user_id', $user->id)
            ->where('push_token', $pushToken)
            ->update(['is_active' => false, 'last_active_at' => now()]) > 0;
    }

    /**
     * Note that a phone is still in use, without changing its registration.
     *
     * Called on app open. It deliberately does not reactivate a device the
     * provider rejected: a token FCM has declared dead comes back dead, and
     * quietly resurrecting it on the next launch would restore the exact
     * loop the deactivation exists to break.
     */
    public function touch(User $user, ?string $pushToken = null): void
    {
        $query = UserDevice::query()
            ->where('user_id', $user->id)
            ->where('is_active', true);

        if ($pushToken !== null) {
            $query->where('push_token', $pushToken);
        }

        $query->update(['last_active_at' => now()]);
    }

    /**
     * Sign a device off without the user asking. Used when a push provider
     * reports the token is no longer valid, and available to the app for a
     * device it knows is gone.
     */
    public function deactivate(User $user, string $pushToken): bool
    {
        return UserDevice::query()
            ->where('user_id', $user->id)
            ->where('push_token', $pushToken)
            ->update(['is_active' => false, 'last_active_at' => now()]) > 0;
    }

    /**
     * The device list the app shows in settings, so a user can see what is
     * registered and remove one they do not recognise.
     */
    public function listFor(User $user, ?string $appType = null)
    {
        return UserDevice::query()
            ->forAppType($appType)
            ->where('user_id', $user->id)
            ->orderByDesc('last_active_at')
            ->get();
    }

    /**
     * A push token belongs to a handset, not to an account. The same person signs
     * out and somebody else signs in on a shared phone, or a customer is created
     * for a booking made on a number that already had the app installed. If the
     * previous owner keeps the row active then their next notification lands on a
     * screen showing somebody else's name, so the token is handed over rather
     * than duplicated.
     *
     * Locked for update because two concurrent registrations for the same token
     * are exactly the race this rule exists for, and without the lock both could
     * read "not mine, nothing to do" and both insert.
     */
    private function releaseTokenFromPreviousOwners(User $user, string $pushToken): void
    {
        UserDevice::query()
            ->where('push_token', $pushToken)
            ->where('user_id', '!=', $user->id)
            ->lockForUpdate()
            ->get()
            ->each(fn (UserDevice $previous) => $previous->forceFill([
                'is_active' => false,
                'last_active_at' => now(),
            ])->save());
    }
}
