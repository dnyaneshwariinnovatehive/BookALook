<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * One approved thing a salon is allowed to say.
 *
 * WhatsApp does not let a business send arbitrary text to someone who has not
 * written in recently — every outbound marketing message must use a template
 * Meta has reviewed. So the catalogue is the platform's, not the salon's: the
 * salon picks a template and fills its blanks.
 *
 * `is_active` is really "Meta has approved this". A template with no
 * meta_template_name has not been submitted yet and cannot be sent.
 */
class CampaignTemplate extends Model
{
    use HasUuids;

    protected $fillable = [
        'key',
        'name',
        'category',
        'description',
        'meta_template_name',
        'language',
        'body_preview',
        'variables',
        'default_audience',
        'min_plan',
        'is_active',
        'sort_order',
    ];

    protected $casts = [
        'variables' => 'array',
        'default_audience' => 'array',
        'is_active' => 'boolean',
    ];

    // The campaign kinds the plan spec names.
    public const CATEGORY_OFFER = 'offer';
    public const CATEGORY_COMBO = 'combo';
    public const CATEGORY_REPEAT_VISIT = 'repeat_visit';
    public const CATEGORY_REACTIVATION = 'reactivation';
    public const CATEGORY_FESTIVAL = 'festival';
    public const CATEGORY_BIRTHDAY = 'birthday';
    public const CATEGORY_ANNOUNCEMENT = 'announcement';
    public const CATEGORY_MEMBERSHIP = 'membership';

    public const CATEGORIES = [
        self::CATEGORY_OFFER => 'Offers',
        self::CATEGORY_COMBO => 'Combo promotions',
        self::CATEGORY_REPEAT_VISIT => 'Repeat visits',
        self::CATEGORY_REACTIVATION => 'Win back customers',
        self::CATEGORY_FESTIVAL => 'Festivals',
        self::CATEGORY_BIRTHDAY => 'Birthdays',
        self::CATEGORY_ANNOUNCEMENT => 'Announcements',
        self::CATEGORY_MEMBERSHIP => 'Memberships',
    ];

    /** Sendable: approved by Meta and switched on here. */
    public function scopeSendable($query)
    {
        return $query->where('is_active', true)->whereNotNull('meta_template_name');
    }

    public function campaigns()
    {
        return $this->hasMany(Campaign::class);
    }

    public function requiresGrowth(): bool
    {
        return $this->min_plan === 'growth';
    }

    /**
     * Fill the placeholders for one recipient.
     *
     * Meta numbers template variables from 1 in the order they appear, so the
     * declared `variables` list is an ordered contract, not a bag of names.
     *
     * @param  array<string, string>  $values
     * @return list<string>
     */
    public function orderedValues(array $values): array
    {
        return array_map(
            fn (array $variable) => (string) ($values[$variable['key']] ?? ''),
            $this->variables ?? []
        );
    }

    /** The preview with {{1}}, {{2}}… replaced, for showing in the app. */
    public function renderPreview(array $values): string
    {
        $body = $this->body_preview;

        foreach ($this->orderedValues($values) as $index => $value) {
            $body = str_replace('{{'.($index + 1).'}}', $value, $body);
        }

        return $body;
    }
}
