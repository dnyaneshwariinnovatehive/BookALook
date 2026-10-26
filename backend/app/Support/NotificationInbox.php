<?php

namespace App\Support;

use App\Models\Notification;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

/**
 * What every inbox shares — customer, salon owner and staff, collaborator: what
 * counts as visible, the date filters, and deleting.
 *
 * Deleting hides the row (dismissed_at) rather than removing it, because the
 * row doubles as the de-duplication record that keeps a reminder from being
 * sent twice. The nightly prune removes it later on the normal retention.
 */
class NotificationInbox
{
    /** The date filters the apps offer, as `?period=`. */
    public const PERIODS = ['today', 'yesterday', 'week', 'month'];

    /** Not hidden by the sender, not deleted by the person. */
    public static function visible(Builder $query): Builder
    {
        return $query
            ->whereNull('dismissed_at')
            ->where(function ($q) {
                $q->whereNull('data->hide_in_app')->orWhere('data->hide_in_app', false);
            });
    }

    /**
     * Narrow to a date filter. Days are the app's own (India) days, not UTC
     * ones, so "today" means today for the person reading it.
     */
    public static function inPeriod(Builder $query, ?string $period): Builder
    {
        $now = Carbon::now();

        return match ($period) {
            'today' => $query->where('created_at', '>=', $now->copy()->startOfDay()),
            'yesterday' => $query
                ->where('created_at', '>=', $now->copy()->subDay()->startOfDay())
                ->where('created_at', '<', $now->copy()->startOfDay()),
            'week' => $query->where('created_at', '>=', $now->copy()->subDays(7)->startOfDay()),
            'month' => $query->where('created_at', '>=', $now->copy()->subDays(30)->startOfDay()),
            default => $query,
        };
    }

    /** The period a request asked for, or null for everything. */
    public static function period(Request $request): ?string
    {
        $period = $request->query('period');

        return in_array($period, self::PERIODS, true) ? $period : null;
    }

    /**
     * Delete from an inbox already scoped to its owner. Either the given ids,
     * or everything in a period, or everything; never anyone else's.
     *
     * @return int How many were deleted.
     */
    public static function dismiss(Builder $scoped, Request $request): int
    {
        $request->validate([
            'ids' => 'nullable|array|max:500',
            'ids.*' => 'string',
            'period' => 'nullable|in:'.implode(',', self::PERIODS),
            'all' => 'nullable|boolean',
        ]);

        $query = self::visible($scoped);

        if ($request->filled('ids')) {
            $query->whereIn('id', $request->input('ids'));
        } elseif ($request->filled('period')) {
            self::inPeriod($query, $request->input('period'));
        } elseif (! $request->boolean('all')) {
            // Nothing said what to delete: delete nothing rather than everything.
            return 0;
        }

        return $query->update(['dismissed_at' => now()]);
    }

    public static function dismissOne(Builder $scoped, string $id): bool
    {
        return self::visible($scoped)->whereKey($id)->update(['dismissed_at' => now()]) > 0;
    }

    /** Base query for one user's own notifications. */
    public static function forUser(string $userId): Builder
    {
        return Notification::query()->where('user_id', $userId);
    }
}
