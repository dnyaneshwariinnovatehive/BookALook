<?php

namespace App\Models;

use App\Support\Notifications\NotificationType;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * What a user has asked not to be told, per app.
 *
 * There is deliberately no "row missing" behaviour to worry about: the accessors
 * below answer for an account that has never opened the settings screen, and
 * they answer with "everything on". A preference table that defaults to silence
 * would mean a fresh install quietly drops every push, which is the kind of bug
 * nobody reports and nobody fixes.
 *
 * The switches that matter are `push_enabled` and `promotional_notifications`.
 * The rest exist so a future category has a home, and are readable so the app
 * can render a settings screen that is not lying about what it can change.
 */
class NotificationPreference extends Model
{
    use HasUuids;

    protected $table = 'notification_preferences';

    protected $guarded = [];

    protected $casts = [
        'push_enabled' => 'boolean',
        'booking_notifications' => 'boolean',
        'appointment_reminders' => 'boolean',
        'payment_notifications' => 'boolean',
        'promotional_notifications' => 'boolean',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /**
     * The switches the API accepts and the app renders, with their defaults.
     *
     * @var array<string, bool>
     */
    public static function defaults(): array
    {
        return [
            'push_enabled' => true,
            'booking_notifications' => true,
            'appointment_reminders' => true,
            'payment_notifications' => true,
            'promotional_notifications' => true,
        ];
    }

    /**
     * The stored row, or a throwaway all-defaults row when the user has never
     * set anything.
     *
     * The returned model may be unsaved, so read from it freely but never
     * `save()` it: saving would insert a row with a null id. Callers that mean to
     * change something upsert with updateOrCreate instead, which is why nothing
     * here writes.
     */
    public static function forUser(string $userId, string $appType): self
    {
        return static::query()
            ->where('user_id', $userId)
            ->where('app_type', $appType)
            ->first()
            ?? new static(array_merge(self::defaults(), [
                'user_id' => $userId,
                'app_type' => $appType,
            ]));
    }

    /**
     * The single question the delivery pipeline asks.
     *
     * A transactional notification is never suppressed. That is the whole reason
     * the category exists: a customer who turned promotional off must still be
     * told their salon cancelled, and a provider who muted marketing must still
     * be told somebody booked them.
     */
    public function allows(string $notificationType): bool
    {
        if (! $this->push_enabled) {
            return false;
        }

        if (NotificationType::isPromotional($notificationType)) {
            return (bool) $this->promotional_notifications;
        }

        return true;
    }

    /**
     * The shape the app's settings screen reads. Defaults are merged in so the
     * screen never has to know a default.
     *
     * @return array<string, bool|string>
     */
    public function toApiArray(): array
    {
        return array_merge(self::defaults(), [
            'push_enabled' => (bool) $this->push_enabled,
            'booking_notifications' => (bool) $this->booking_notifications,
            'appointment_reminders' => (bool) $this->appointment_reminders,
            'payment_notifications' => (bool) $this->payment_notifications,
            'promotional_notifications' => (bool) $this->promotional_notifications,
            'app_type' => $this->app_type,
        ]);
    }
}
