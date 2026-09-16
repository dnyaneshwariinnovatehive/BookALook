<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

/**
 * Reading the audit trail.
 *
 * There is no write endpoint, no edit and no delete, on purpose — entries are
 * only ever created as a side effect of the action they describe. An audit log
 * with an API that can change it proves nothing.
 *
 * The filters are built around the questions people actually bring to a log:
 * "what happened to this salon", "what did this person do", "what changed last
 * Tuesday", and "show me only the serious things".
 */
class AuditLogController extends Controller
{
    private const PER_PAGE = 50;

    public function index(Request $request)
    {
        $request->validate([
            'page' => 'nullable|integer|min:1',
            'actor_id' => 'nullable|uuid',
            'category' => 'nullable|string|max:40',
            'severity' => 'nullable|in:normal,high,critical',
            'entity_id' => 'nullable|uuid',
            'search' => 'nullable|string|max:120',
            // Days back from today. Null means everything ever.
            'within_days' => 'nullable|integer|min:1|max:3650',
            'from' => 'nullable|date',
            'to' => 'nullable|date',
        ]);

        // created_at only resolves to the second, so id breaks the tie — it is
        // time-ordered, which keeps two actions taken in the same breath in the
        // sequence they actually happened.
        $query = AuditLog::with('actor:id,name,role')
            ->orderByDesc('created_at')
            ->orderByDesc('id');

        if ($request->filled('actor_id')) {
            $query->where('actor_id', $request->actor_id);
        }

        if ($request->filled('entity_id')) {
            $query->where('entity_id', $request->entity_id);
        }

        // Category and severity are properties of the action, not columns, so
        // they resolve to the set of actions that carry them.
        if ($request->filled('category')) {
            $query->whereIn('action', $this->actionsWhere('category', $request->category));
        }

        if ($request->filled('severity')) {
            $query->whereIn('action', $this->actionsWhere('severity', $request->severity));
        }

        if ($request->filled('within_days')) {
            $query->where('created_at', '>=', Carbon::today()->subDays((int) $request->within_days));
        }

        if ($request->filled('from')) {
            $query->where('created_at', '>=', Carbon::parse($request->from)->startOfDay());
        }

        if ($request->filled('to')) {
            $query->where('created_at', '<=', Carbon::parse($request->to)->endOfDay());
        }

        // Searches the name of the thing acted on and the reason typed at the
        // time — both live in metadata, which is where the words are.
        if ($request->filled('search')) {
            $term = '%' . $request->search . '%';
            $query->where(function ($q) use ($term) {
                $q->where('metadata', 'like', $term)
                    ->orWhere('action', 'like', $term)
                    ->orWhereHas('actor', fn ($a) => $a->where('name', 'like', $term));
            });
        }

        $page = $query->paginate(self::PER_PAGE, ['*'], 'page', (int) $request->input('page', 1));

        return response()->json([
            'success' => true,
            'data' => collect($page->items())->map(fn (AuditLog $entry) => $this->present($entry))->values(),
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'total' => $page->total(),
                'has_more' => $page->hasMorePages(),
            ],
            'filters' => [
                'categories' => AuditLog::CATEGORIES,
                // Only people who have actually done something appear, so the
                // dropdown is never a list of names with nothing behind them.
                'actors' => User::whereIn('id', AuditLog::select('actor_id')->distinct())
                    ->orderBy('name')
                    ->get(['id', 'name', 'role']),
            ],
            'summary' => $this->summary(),
        ]);
    }

    /**
     * Enough of a headline to notice something unusual without reading the log.
     *
     * @return array<string, mixed>
     */
    private function summary(): array
    {
        $since = Carbon::today()->subDays(7);

        return [
            'total' => AuditLog::count(),
            'last_7_days' => AuditLog::where('created_at', '>=', $since)->count(),
            'critical_last_7_days' => AuditLog::where('created_at', '>=', $since)
                ->whereIn('action', $this->actionsWhere('severity', 'critical'))
                ->count(),
            'active_actors_last_7_days' => AuditLog::where('created_at', '>=', $since)
                ->distinct('actor_id')
                ->count('actor_id'),
        ];
    }

    /** @return array<int, string> */
    private function actionsWhere(string $key, string $value): array
    {
        return array_keys(array_filter(
            AuditLog::CATALOGUE,
            fn ($meta) => ($meta[$key] ?? null) === $value
        ));
    }

    /** @return array<string, mixed> */
    private function present(AuditLog $entry): array
    {
        $described = $entry->describe();

        return [
            'id' => $entry->id,
            'action' => $entry->action,
            'action_label' => $described['label'],
            'category' => $described['category'],
            'severity' => $described['severity'],

            'actor_name' => $entry->actor->name ?? 'Deleted account',
            'actor_role' => $entry->actor->role ?? null,

            'entity_type' => $entry->entity_type,
            'entity_id' => $entry->entity_id,
            'entity_label' => $entry->subjectLabel(),

            'field_name' => $entry->field_name,
            'changes' => $this->changes($entry),
            // The reason someone typed at the time is the single most useful
            // thing in the row; it is lifted out of metadata so the list can
            // show it without the reader opening anything.
            'reason' => $entry->metadata['reason'] ?? null,
            'metadata' => $this->readableMetadata($entry),

            'ip_address' => $entry->ip_address,
            // Absolute, always. A relative label alone is useless for an audit
            // trail — "2 hours ago" stops meaning anything tomorrow.
            'created_at' => $entry->created_at?->toIso8601String(),
            'occurred_on' => $entry->created_at?->toDateString(),
            'occurred_at' => $entry->created_at?->format('H:i'),
        ];
    }

    /**
     * Field-by-field before and after, flattened for display.
     *
     * @return array<int, array{field: string, from: mixed, to: mixed}>
     */
    private function changes(AuditLog $entry): array
    {
        $before = $entry->old_value ?? [];
        $after = $entry->new_value ?? [];

        if (! is_array($before) || ! is_array($after)) {
            return [];
        }

        $fields = array_unique(array_merge(array_keys($before), array_keys($after)));
        $changes = [];

        foreach ($fields as $field) {
            $from = $before[$field] ?? null;
            $to = $after[$field] ?? null;

            if ($from === $to) {
                continue;
            }

            $changes[] = [
                'field' => str_replace('_', ' ', $field),
                'from' => $this->scalarise($from),
                'to' => $this->scalarise($to),
            ];
        }

        return $changes;
    }

    /** Metadata minus the bits already surfaced on their own. */
    private function readableMetadata(AuditLog $entry): ?array
    {
        $metadata = $entry->metadata ?? [];
        unset($metadata['entity_label'], $metadata['reason']);

        return $metadata ?: null;
    }

    private function scalarise(mixed $value): mixed
    {
        if (is_bool($value)) {
            return $value ? 'yes' : 'no';
        }

        if (is_array($value)) {
            return json_encode($value);
        }

        return $value;
    }
}
