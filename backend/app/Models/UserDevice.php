<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * One phone that wants to be pushed to.
 *
 * The row is keyed to a user, but the thing that actually identifies it is the
 * push token: install the app as Sam, sign out, sign in as Alex, and it is the
 * same token on the same handset. Registration therefore hands the token over
 * rather than letting two accounts both believe they own it.
 */
class UserDevice extends Model
{
    use HasUuids;

    public const APP_TYPE_CUSTOMER = 'customer_app';
    public const APP_TYPE_PARTNER = 'partner_app';

    public const PLATFORM_ANDROID = 'android';
    public const PLATFORM_IOS = 'ios';

    protected $guarded = [];

    /**
     * The table has no created_at or updated_at — it was created without
     * $table->timestamps() and never revisited. Telling Eloquent so stops it
     * trying to write columns that are not there on every save, and leaves the
     * table as it is rather than quietly widening the schema to suit the model.
     */
    public const CREATED_AT = null;

    public const UPDATED_AT = null;

    protected $casts = [
        'last_active_at' => 'datetime',
        'is_active' => 'boolean',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function deliveries(): HasMany
    {
        return $this->hasMany(NotificationDelivery::class);
    }

    /**
     * Signed in, not logged out, and still holding a token worth sending to.
     *
     * `push_token != ''` matters as much as the null check: a phone that
     * registered before it was granted notification permission, or one whose
     * token has been cleared, leaves an empty string behind rather than a null.
     */
    public function scopePushable($query)
    {
        return $query->where('is_active', true)
            ->whereNotNull('push_token')
            ->where('push_token', '!=', '');
    }

    /**
     * Enough of the token to recognise it in a log line, never enough to use.
     *
     * Log lines are the one place this token is guaranteed to escape the
     * database, so the mask is the last thing standing between a log dump and
     * somebody pushing arbitrary content to a customer's phone. Short tokens
     * are masked completely — there is no "safe" prefix on a short secret.
     */
    public function maskedToken(): ?string
    {
        $token = $this->push_token;

        if ($token === null || $token === '') {
            return null;
        }

        $length = mb_strlen($token);

        if ($length <= 12) {
            return str_repeat('*', $length);
        }

        return mb_substr($token, 0, 8).'...'.mb_substr($token, -4);
    }
}
