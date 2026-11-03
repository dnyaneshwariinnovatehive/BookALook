<?php

namespace App\Models;

use Illuminate\Support\Carbon;
use Laravel\Sanctum\PersonalAccessToken as SanctumToken;

/**
 * Sanctum's token, minus a database write on almost every request.
 *
 * Sanctum stamps `last_used_at` and saves the token on EVERY authenticated
 * request — a write to PostgreSQL for each tap a signed-in customer or partner
 * makes. Nothing in BookALook reads that column to the second (expiry uses
 * created_at / expires_at), so the stamp is saved at most once every
 * STAMP_MINUTES per token. Any other change to a token saves as normal.
 */
class PersonalAccessToken extends SanctumToken
{
    public const STAMP_MINUTES = 10;

    public function save(array $options = []): bool
    {
        if ($this->exists && array_keys($this->getDirty()) === ['last_used_at']) {
            $previous = $this->getOriginal('last_used_at');

            if ($previous && Carbon::parse($previous)->gt(now()->subMinutes(self::STAMP_MINUTES))) {
                // Recent enough: keep the old stamp, skip the write.
                $this->syncOriginalAttribute('last_used_at');

                return true;
            }
        }

        return parent::save($options);
    }
}
