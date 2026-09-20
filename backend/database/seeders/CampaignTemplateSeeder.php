<?php

namespace Database\Seeders;

use App\Models\CampaignTemplate;
use App\Services\Marketing\AudienceBuilder;
use Illuminate\Database\Seeder;

/**
 * The starting catalogue: the campaign kinds the plan spec names.
 *
 * Every one of these ships with `is_active` false and no meta_template_name,
 * because neither is ours to decide — a template is sendable when Meta has
 * approved it and somebody has pasted the approved name in. Seeding them as
 * ready would let a salon press send on a template that does not exist at the
 * other end.
 *
 * The copy here is what should be submitted to Meta, near enough word for word.
 * Meta reviews the text, so the approved template must match what the app shows
 * a salon it is about to send.
 */
class CampaignTemplateSeeder extends Seeder
{
    public function run(): void
    {
        foreach ($this->templates() as $index => $template) {
            CampaignTemplate::updateOrCreate(
                ['key' => $template['key']],
                $template + ['sort_order' => $index * 10]
            );
        }
    }

    /** @return array<int, array<string, mixed>> */
    private function templates(): array
    {
        // Two variables nearly every template wants, filled per recipient.
        $who = ['key' => 'customer_name', 'label' => 'Customer name', 'example' => 'Priya', 'source' => 'customer'];
        $salon = ['key' => 'salon_name', 'label' => 'Salon name', 'example' => 'Glow Up Studio', 'source' => 'salon'];

        return [
            [
                'key' => 'offer_percentage',
                'name' => 'Discount offer',
                'category' => CampaignTemplate::CATEGORY_OFFER,
                'description' => 'A straight percentage off, to everyone or to a group you choose.',
                'body_preview' => "Hi {{1}}! {{2}} is running {{3}} off {{4}} until {{5}}. Book your slot on the BookALook app.",
                'variables' => [
                    $who,
                    $salon,
                    ['key' => 'discount', 'label' => 'Discount', 'example' => '20%', 'source' => 'input'],
                    ['key' => 'scope', 'label' => 'What it applies to', 'example' => 'all hair services', 'source' => 'input'],
                    ['key' => 'valid_until', 'label' => 'Valid until', 'example' => '30 September', 'source' => 'input'],
                ],
                'default_audience' => ['segment' => AudienceBuilder::SEGMENT_ALL],
                'min_plan' => 'starter',
            ],
            [
                'key' => 'combo_promotion',
                'name' => 'Combo promotion',
                'category' => CampaignTemplate::CATEGORY_COMBO,
                'description' => 'Promote a package at its combined price — the higher-bill campaign.',
                'body_preview' => "Hi {{1}}! Save {{2}} at {{3}}: our {{4}} package is {{5}} when booked together. Book on the BookALook app.",
                'variables' => [
                    $who,
                    ['key' => 'saving', 'label' => 'Saving', 'example' => '₹400', 'source' => 'input'],
                    $salon,
                    ['key' => 'combo_name', 'label' => 'Combo name', 'example' => 'Haircut + Beard Trim', 'source' => 'input'],
                    ['key' => 'combo_price', 'label' => 'Combo price', 'example' => '₹899', 'source' => 'input'],
                ],
                'default_audience' => ['segment' => AudienceBuilder::SEGMENT_ALL],
                'min_plan' => 'starter',
            ],
            [
                'key' => 'repeat_visit_reminder',
                'name' => 'Time for your next visit',
                'category' => CampaignTemplate::CATEGORY_REPEAT_VISIT,
                'description' => 'A nudge to regulars who are about due for their usual appointment.',
                'body_preview' => "Hi {{1}}, it has been a while since your last visit to {{2}}. Ready for your next {{3}}? Book on the BookALook app.",
                'variables' => [
                    $who,
                    $salon,
                    ['key' => 'service', 'label' => 'Service', 'example' => 'haircut', 'source' => 'input'],
                ],
                'default_audience' => ['segment' => AudienceBuilder::SEGMENT_REPEAT],
                'min_plan' => 'starter',
            ],
            [
                'key' => 'reactivation',
                'name' => 'We miss you',
                'category' => CampaignTemplate::CATEGORY_REACTIVATION,
                'description' => 'Win back customers who have not been in for a while, usually with an incentive.',
                'body_preview' => "Hi {{1}}, we have not seen you at {{2}} in a while. Here is {{3}} off your next visit — book on the BookALook app.",
                'variables' => [
                    $who,
                    $salon,
                    ['key' => 'incentive', 'label' => 'Incentive', 'example' => '15%', 'source' => 'input'],
                ],
                'default_audience' => ['segment' => AudienceBuilder::SEGMENT_INACTIVE],
                'min_plan' => 'starter',
            ],
            [
                'key' => 'festival_offer',
                'name' => 'Festival offer',
                'category' => CampaignTemplate::CATEGORY_FESTIVAL,
                'description' => 'Seasonal campaigns — Diwali, Eid, New Year and the rest.',
                'body_preview' => "Happy {{1}}, {{2}}! {{3}} is offering {{4}} to celebrate. Valid until {{5}}. Book on the BookALook app.",
                'variables' => [
                    ['key' => 'festival', 'label' => 'Festival', 'example' => 'Diwali', 'source' => 'input'],
                    $who,
                    $salon,
                    ['key' => 'offer', 'label' => 'Offer', 'example' => '25% off all services', 'source' => 'input'],
                    ['key' => 'valid_until', 'label' => 'Valid until', 'example' => '5 November', 'source' => 'input'],
                ],
                'default_audience' => ['segment' => AudienceBuilder::SEGMENT_ALL],
                'min_plan' => 'starter',
            ],
            [
                'key' => 'birthday_offer',
                'name' => 'Birthday offer',
                'category' => CampaignTemplate::CATEGORY_BIRTHDAY,
                'description' => 'Only reaches customers with an account, since a walk-in never leaves a birth date.',
                'body_preview' => "Happy birthday {{1}}! {{2}} would like to treat you — {{3}} off any service this month. Book on the BookALook app.",
                'variables' => [
                    $who,
                    $salon,
                    ['key' => 'gift', 'label' => 'Birthday offer', 'example' => '20%', 'source' => 'input'],
                ],
                'default_audience' => ['segment' => AudienceBuilder::SEGMENT_BIRTHDAY, 'birthday_window' => 7],
                'min_plan' => 'starter',
            ],
            [
                'key' => 'new_service',
                'name' => 'New service announcement',
                'category' => CampaignTemplate::CATEGORY_ANNOUNCEMENT,
                'description' => 'Tell customers about something you have just started offering.',
                'body_preview' => "Hi {{1}}! {{2}} now offers {{3}}, from {{4}}. Book on the BookALook app.",
                'variables' => [
                    $who,
                    $salon,
                    ['key' => 'service', 'label' => 'New service', 'example' => 'keratin treatment', 'source' => 'input'],
                    ['key' => 'price', 'label' => 'Starting price', 'example' => '₹1,499', 'source' => 'input'],
                ],
                'default_audience' => ['segment' => AudienceBuilder::SEGMENT_ALL],
                'min_plan' => 'starter',
            ],
            [
                'key' => 'vip_exclusive',
                'name' => 'Exclusive offer for best customers',
                'category' => CampaignTemplate::CATEGORY_MEMBERSHIP,
                'description' => 'For your highest-spending regulars. Needs high-value targeting, so Growth only.',
                'body_preview' => "Hi {{1}}, as one of our regulars at {{2}} we would like to offer you {{3}}. Valid until {{4}} — book on the BookALook app.",
                'variables' => [
                    $who,
                    $salon,
                    ['key' => 'offer', 'label' => 'Offer', 'example' => 'a complimentary head massage', 'source' => 'input'],
                    ['key' => 'valid_until', 'label' => 'Valid until', 'example' => '31 October', 'source' => 'input'],
                ],
                'default_audience' => ['segment' => AudienceBuilder::SEGMENT_HIGH_VALUE],
                'min_plan' => 'growth',
            ],
        ];
    }
}
