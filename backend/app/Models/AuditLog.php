<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

/**
 * One thing a SuperAdmin did that somebody might later need to account for.
 *
 * Append-only by intention. There is no update path and no delete path in the
 * application, because a record that can be edited is not evidence of anything.
 *
 * Every row carries a human-readable label for whatever it acted on, captured
 * at the time of writing rather than joined at read time. A salon can be
 * deleted; the fact that someone suspended it on a Tuesday cannot stop being
 * true, and the log has to still say which salon.
 */
class AuditLog extends Model
{
    use HasUuids;

    protected $table = 'audit_log';

    protected $fillable = [
        'actor_id',
        'action',
        'entity_type',
        'entity_id',
        'field_name',
        'old_value',
        'new_value',
        'metadata',
        'ip_address',
        'user_agent',
        'request_id',
    ];

    protected $casts = [
        'old_value' => 'array',
        'new_value' => 'array',
        'metadata' => 'array',
    ];

    /**
     * Time-ordered ids rather than random ones.
     *
     * created_at only resolves to the second, and two actions a second apart
     * are common — suspending a salon and reinstating it in the same breath
     * produced entries the log could not put in order, which for a record of
     * who did what when is not a cosmetic problem. An ordered UUID carries its
     * own timestamp, so id becomes an exact tiebreaker.
     */
    public function newUniqueId(): string
    {
        return (string) \Illuminate\Support\Str::orderedUuid();
    }

    // ------------------------------------------------------------- actions

    // Salons — who is allowed to trade.
    public const SALON_APPROVED = 'salon.approved';
    public const SALON_REJECTED = 'salon.rejected';
    public const SALON_SUSPENDED = 'salon.suspended';
    public const SALON_REINSTATED = 'salon.reinstated';
    public const SALON_COLLABORATOR_ASSIGNED = 'salon.collaborator_assigned';

    // Moderation — what was done about a complaint.
    public const COMPLAINT_WARNING_SENT = 'complaint.warning_sent';
    public const COMPLAINT_DISMISSED = 'complaint.dismissed';

    // Money — anything that changes what a salon pays or is paid.
    public const SUBSCRIPTION_ASSIGNED = 'subscription.assigned';
    public const COMMISSION_RATE_CHANGED = 'commission.rate_changed';
    public const PLAN_CREATED = 'plan.created';
    public const PLAN_UPDATED = 'plan.updated';
    public const PLAN_DELETED = 'plan.deleted';
    public const PAYOUT_APPROVED = 'payout.approved';
    public const PAYOUT_DISTRIBUTED = 'payout.distributed';

    // Platform settings — rules everybody is bound by.
    public const POLICY_UPDATED = 'policy.updated';
    public const SUB_AREAS_IMPORTED = 'sub_area.imported';

    // People.
    public const COLLABORATOR_CREATED = 'collaborator.created';

    /**
     * How each action reads, where it belongs, and how much it matters.
     *
     * Severity is not decoration. A log where every line looks identical is a
     * log nobody reads, and the three things that genuinely need to leap out
     * are: a salon losing access, money moving, and the platform's own rules
     * changing.
     *
     * @var array<string, array{label: string, category: string, severity: string}>
     */
    public const CATALOGUE = [
        self::SALON_APPROVED => ['label' => 'Approved a salon', 'category' => 'Salons', 'severity' => 'normal'],
        self::SALON_REJECTED => ['label' => 'Rejected a salon', 'category' => 'Salons', 'severity' => 'high'],
        self::SALON_SUSPENDED => ['label' => 'Suspended a salon', 'category' => 'Salons', 'severity' => 'critical'],
        self::SALON_REINSTATED => ['label' => 'Put a salon back online', 'category' => 'Salons', 'severity' => 'high'],
        self::SALON_COLLABORATOR_ASSIGNED => ['label' => 'Assigned a collaborator', 'category' => 'Salons', 'severity' => 'normal'],

        self::COMPLAINT_WARNING_SENT => ['label' => 'Sent a warning', 'category' => 'Moderation', 'severity' => 'high'],
        self::COMPLAINT_DISMISSED => ['label' => 'Dismissed a complaint', 'category' => 'Moderation', 'severity' => 'normal'],

        self::SUBSCRIPTION_ASSIGNED => ['label' => 'Changed a salon\'s plan', 'category' => 'Money', 'severity' => 'high'],
        self::COMMISSION_RATE_CHANGED => ['label' => 'Changed a commission rate', 'category' => 'Money', 'severity' => 'critical'],
        self::PLAN_CREATED => ['label' => 'Created a plan', 'category' => 'Money', 'severity' => 'high'],
        self::PLAN_UPDATED => ['label' => 'Edited a plan', 'category' => 'Money', 'severity' => 'high'],
        self::PLAN_DELETED => ['label' => 'Deleted a plan', 'category' => 'Money', 'severity' => 'critical'],
        self::PAYOUT_APPROVED => ['label' => 'Approved a payout', 'category' => 'Money', 'severity' => 'high'],
        self::PAYOUT_DISTRIBUTED => ['label' => 'Distributed a payout', 'category' => 'Money', 'severity' => 'critical'],

        self::POLICY_UPDATED => ['label' => 'Changed platform policy', 'category' => 'Settings', 'severity' => 'critical'],
        // A bulk write to the list every address on the platform points at.
        self::SUB_AREAS_IMPORTED => ['label' => 'Imported areas from a file', 'category' => 'Settings', 'severity' => 'high'],

        self::COLLABORATOR_CREATED => ['label' => 'Added a collaborator', 'category' => 'People', 'severity' => 'normal'],
    ];

    /** Every category, for the filter bar. */
    public const CATEGORIES = ['Salons', 'Moderation', 'Money', 'Settings', 'People'];

    public function actor()
    {
        return $this->belongsTo(User::class, 'actor_id');
    }

    /** @return array{label: string, category: string, severity: string} */
    public function describe(): array
    {
        return self::CATALOGUE[$this->action] ?? [
            'label' => str_replace(['.', '_'], [' — ', ' '], $this->action),
            'category' => 'Other',
            'severity' => 'normal',
        ];
    }

    /** The thing acted on, as it was named at the time. */
    public function subjectLabel(): ?string
    {
        return ($this->metadata ?? [])['entity_label'] ?? null;
    }
}
