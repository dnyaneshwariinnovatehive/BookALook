<?php

namespace App\Services;

use App\Models\AuditLog;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * Writes the audit trail.
 *
 * Two rules govern everything here.
 *
 * First, logging must never break the thing it is recording. A SuperAdmin
 * suspending a dangerous salon must not be stopped because the audit table had
 * a bad day — so every write is wrapped, and a failure goes to the application
 * log instead of to the user. The trade is deliberate: a missing audit row is
 * bad, a blocked suspension is worse.
 *
 * Second, a row has to stay readable forever. Entity names are captured at
 * write time rather than joined on read, because the salon in "suspended Glow
 * Up Studio" may not exist by the time anyone reads the line — and "suspended
 * a2b1f0a0-91a0…" is not an audit trail, it is a puzzle.
 */
class AuditLogger
{
    /**
     * Record something a SuperAdmin did.
     *
     * @param  string  $action  One of AuditLog's action constants.
     * @param  Model|null  $entity  What it was done to.
     * @param  string|null  $label  How that thing should read, now and later.
     * @param  array<string, mixed>|null  $before  State before, for changes.
     * @param  array<string, mixed>|null  $after  State after.
     * @param  array<string, mixed>  $metadata  Anything else worth keeping —
     *                                          the reason typed, the complaint
     *                                          it came from.
     */
    public static function record(
        string $action,
        ?Model $entity = null,
        ?string $label = null,
        ?array $before = null,
        ?array $after = null,
        array $metadata = [],
    ): ?AuditLog {
        try {
            $request = request();
            // Either source is fine; they disagree only in artificial contexts
            // such as a console script standing in for a request.
            $actorId = $request?->user()?->id ?? auth()->id();

            // Nothing to attribute it to. A row with no actor answers the one
            // question an audit log exists to answer, so it is not written —
            // but the attempt is worth knowing about.
            if (! $actorId) {
                Log::warning('Audit entry skipped: no authenticated actor', [
                    'action' => $action,
                    'entity_id' => $entity?->getKey(),
                ]);

                return null;
            }

            if ($label !== null) {
                $metadata['entity_label'] = $label;
            }

            return AuditLog::create([
                'actor_id' => $actorId,
                'action' => $action,
                'entity_type' => $entity ? class_basename($entity) : 'Platform',
                'entity_id' => self::uuidOrNull($entity?->getKey()),
                // Only meaningful when exactly one field moved; multi-field
                // changes live in old_value/new_value as objects.
                'field_name' => self::soleChangedField($before, $after),
                'old_value' => $before,
                'new_value' => $after,
                'metadata' => $metadata ?: null,
                'ip_address' => $request?->ip(),
                'user_agent' => Str::limit((string) $request?->userAgent(), 500, ''),
                'request_id' => $request?->header('X-Request-Id'),
            ]);
        } catch (\Throwable $e) {
            Log::error('Audit entry could not be written', [
                'action' => $action,
                'error' => $e->getMessage(),
            ]);

            return null;
        }
    }

    /**
     * The entity_id column is a uuid. Some entities — subscription payment
     * requests, for one — use auto-increment integers, and forcing those into
     * a uuid column would throw. Their id still travels in the metadata.
     */
    private static function uuidOrNull(mixed $key): ?string
    {
        return is_string($key) && Str::isUuid($key) ? $key : null;
    }

    /**
     * When a single field changed, name it — that is what makes a log skimmable
     * ("commission_percentage: 12 → 18"). Two or more and the name would be a
     * lie, so it stays null.
     */
    private static function soleChangedField(?array $before, ?array $after): ?string
    {
        if (! is_array($before) || ! is_array($after)) {
            return null;
        }

        $changed = array_keys(array_diff_assoc(
            array_map(fn ($v) => is_scalar($v) || $v === null ? $v : json_encode($v), $after),
            array_map(fn ($v) => is_scalar($v) || $v === null ? $v : json_encode($v), $before),
        ));

        return count($changed) === 1 ? $changed[0] : null;
    }
}
