<?php

namespace App\Console\Commands;

use App\Models\Appointment;
use App\Models\AppointmentService as AppointmentLine;
use App\Models\Banner;
use App\Models\City;
use App\Models\Combo;
use App\Models\PlatformPolicySetting;
use App\Models\ProviderLeave;
use App\Models\Salon;
use App\Models\SalonEnquiry;
use App\Models\SalonSubscription;
use App\Models\SalonWorkingHour;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\ServiceProvider;
use App\Models\ServiceTemplate;
use App\Models\SubscriptionPaymentRequest;
use App\Models\SubscriptionPlan;
use App\Models\User;
use App\Models\WalletScheme;
use App\Models\WalletSchemeTier;
use App\Services\AppointmentCheckInService;
use App\Services\CommissionService;
use App\Services\PayoutService;
use App\Services\WalletService;
use App\Support\BillingModel;
use App\Support\PayoutCycle;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * A marketplace that looks like it has been running for three months.
 *
 * Built to be shown to somebody. Every screen a demo walks through should have
 * something real on it: the approval queue has salons waiting, the payout run
 * has money in three different states, the coin ladder has salons partway up
 * it, and the subscription queue has a request that needs a decision.
 *
 * The data is deliberately uneven. Salons differ in size, rating, city and how
 * they pay; a couple are lapsed or waiting for approval, because a marketplace
 * where everything is healthy is not a marketplace anyone believes.
 *
 * Destructive by design: it clears trading history and rebuilds it, so it can
 * be run again the morning of a demo and give the same story.
 */
class SeedDemoData extends Command
{
    protected $signature = 'app:seed-demo
        {--keep-history : Leave existing appointments and payouts in place}';

    protected $description = 'Wipe trading history and rebuild a full demo marketplace';

    /** Every seeded phone starts here, and they all log in with OTP 123456. */
    private const PHONE_PREFIX = '98';

    /** How far back the marketplace pretends to have been running. */
    private const WEEKS_OF_HISTORY = 12;

    private User $superAdmin;

    /** @var array<int, User> */
    private array $customers = [];

    /** @var array<string, City> */
    private array $cities = [];

    private SubscriptionPlan $starter;
    private SubscriptionPlan $growth;

    /** @var array<int, Salon> */
    private array $tradingSalons = [];

    /** How many bookings a week each salon takes, keyed by salon id. */
    private array $busyness = [];

    /** Roughly how well each salon should end up rated, keyed by salon id. */
    private array $targetRating = [];

    /** The categories this command owns, so service lookups cannot stray. */
    private array $catalogCategoryIds = [];

    public function handle(): int
    {
        $this->superAdmin = User::where('role', 'superadmin')->firstOrFail();

        if (! $this->option('keep-history')) {
            $this->clearTradingHistory();
        }

        $this->components->info('Platform');
        $this->seedPolicySettings();
        $this->seedCities();
        $this->seedPlans();
        $this->seedWalletScheme();
        // Before the catalogue, so no stray template still has a service
        // hanging off it when duplicates are merged away.
        $this->retireLegacySalons();
        $this->seedCatalog();
        $this->seedBanners();

        $this->components->info('People');
        $this->customers = $this->seedCustomers();
        $this->seedCollaborators();

        $this->components->info('Salons');
        foreach ($this->salonBlueprints() as $blueprint) {
            $this->seedSalon($blueprint);
        }

        $this->components->info('Trading');
        foreach ($this->tradingSalons as $salon) {
            $this->seedHistory($salon);
            $this->seedTodaysBoard($salon);
            $this->seedUpcoming($salon);
            $this->seedLeave($salon);
        }

        $this->components->info('Money');
        $this->seedPayouts();
        $this->seedWalletRedemptions();
        $this->seedPayroll();

        $this->tidyLeftovers();

        $this->components->info('Queues');
        $this->seedEnquiries();
        $this->seedSubscriptionRequests();

        $this->summary();

        return self::SUCCESS;
    }

    // ------------------------------------------------------------- the wipe

    /**
     * Clear everything that represents trading.
     *
     * Reference data — cities, the catalogue, accounts — survives, because
     * rebuilding it would invalidate logins the demo depends on.
     */
    private function clearTradingHistory(): void
    {
        $this->components->warn('Clearing old trading history');

        // Order matters: everything pointing at an appointment has to go
        // before the appointments themselves, or the foreign keys refuse.
        $inOrder = [
            'coupon_redemptions',
            'payment_refunds',
            'payment_allocations',
            'payments',
            'payment_orders',
            'salon_payout_items',
            'appointment_service_additions',
            'appointment_services',
            'reviews',
            'complaints',
            'whatsapp_messages',
            'wallet_transactions',
            'notifications',
            'appointments',

            'salon_payouts',
            'salary_payouts',
            'salon_wallets',
            'cart_items',
            'carts',
            'provider_leaves',
            'salon_closures',
            'subscription_payment_requests',
        ];

        foreach ($inOrder as $table) {
            if (Schema::hasTable($table)) {
                DB::table($table)->delete();
            }
        }

        $this->components->twoColumnDetail(
            'cleared',
            'appointments, payouts, payroll, wallets, carts, notifications'
        );
    }

    // ------------------------------------------------------------- platform

    private function seedPolicySettings(): void
    {
        $settings = [
            'cancellation_cutoff_minutes' => [90, 'integer', 'Minutes before the slot a customer may still cancel.'],
            'reschedule_cutoff_minutes' => [90, 'integer', 'Minutes before the slot a customer may still move it.'],
            'appointment_start_early_minutes' => [30, 'integer', 'How early a session may be started.'],
            'qr_validity_minutes' => [60, 'integer', 'How long a booking QR stays scannable.'],
            'same_day_change_abuse_threshold' => [2, 'integer', 'Same-day changes before a customer is flagged.'],
            'subscription_expiry_warning_days' => [5, 'integer', 'Days of warning before a plan lapses.'],
            'coin_value_inr' => [2.0, 'decimal', 'What one reward coin is worth in rupees.'],
            'subscription_reminder_hour' => [11, 'integer', 'Local hour the renewal reminder goes out.'],
            'commission_settlement_grace_days' => [7, 'integer', 'Days after a month closes before an unsettled Commission Model salon is locked.'],
        ];

        foreach ($settings as $key => [$value, $type, $description]) {
            PlatformPolicySetting::updateOrCreate(
                ['setting_key' => $key],
                [
                    'setting_value' => (string) $value,
                    'data_type' => $type,
                    'description' => $description,
                    'updated_by' => $this->superAdmin->id,
                ]
            );
        }

        $this->components->twoColumnDetail('policy', count($settings) . ' settings · coin worth ₹2.00');
    }

    private function seedCities(): void
    {
        foreach (['Pune', 'Mumbai', 'Bangalore', 'Nashik'] as $name) {
            $city = City::where('name', $name)->first();

            if ($city) {
                $city->forceFill(['is_active' => true])->save();
                $this->cities[$name] = $city;
            }
        }

        $this->components->twoColumnDetail('cities', implode(', ', array_keys($this->cities)));
    }

    /**
     * Two plans, and nothing else.
     *
     * Growth also carries the Commission Model: a salon either buys it up
     * front, or is put on commission and enjoys the same benefits for a
     * percentage of what it bills.
     */
    private function seedPlans(): void
    {
        $this->starter = SubscriptionPlan::updateOrCreate(
            ['name' => 'Starter'],
            [
                'price' => 1999.00,
                'validity_days' => 30,
                'whatsapp_campaign_limit' => 250,
                'has_customer_segmentation' => true,
                'has_service_based_targeting' => false,
                'has_high_value_targeting' => false,
                'has_advanced_insights' => false,
                'has_upsell_recommendations' => 'basic',
                'has_cross_sell_recommendations' => 'none',
                'has_priority_visibility' => false,
                'is_active' => true,
                'created_by' => $this->superAdmin->id,
            ]
        );

        $this->growth = SubscriptionPlan::updateOrCreate(
            ['name' => 'Growth'],
            [
                'price' => 2999.00,
                'validity_days' => 30,
                'whatsapp_campaign_limit' => 1000,
                'has_customer_segmentation' => true,
                'has_service_based_targeting' => true,
                'has_high_value_targeting' => true,
                'has_advanced_insights' => true,
                'has_upsell_recommendations' => 'advanced',
                'has_cross_sell_recommendations' => 'advanced',
                'has_priority_visibility' => true,
                'is_active' => true,
                'created_by' => $this->superAdmin->id,
            ]
        );

        // Anything the platform used to sell is retired, so the demo shows the
        // two plans and only those two.
        $retired = SubscriptionPlan::whereNotIn('id', [$this->starter->id, $this->growth->id])->get();

        foreach ($retired as $plan) {
            SalonSubscription::where('plan_id', $plan->id)
                ->update(['plan_id' => $this->starter->id]);
            $plan->delete();
        }

        app(CommissionService::class)->setPlan($this->growth);

        $this->components->twoColumnDetail('plans', 'Starter ₹1,999/month · Growth ₹2,999/month');
        $this->components->twoColumnDetail('commission benefits', 'Growth' . ($retired->count() ? " · {$retired->count()} old plan(s) retired" : ''));
    }

    private function seedWalletScheme(): void
    {
        WalletScheme::query()->update(['is_active' => false]);

        $scheme = WalletScheme::updateOrCreate(
            ['name' => 'Launch rewards 2026'],
            [
                'description' => 'Coins on every completed online appointment. The more a salon takes, the more each one is worth.',
                'award_mode' => WalletScheme::MODE_PER_APPOINTMENT,
                'is_active' => true,
                'starts_on' => Carbon::today()->subMonths(4)->toDateString(),
                'ends_on' => null,
                'created_by' => $this->superAdmin->id,
            ]
        );

        $scheme->tiers()->delete();

        $ladder = [
            [1, 100, 1],
            [101, 300, 2],
            [301, 600, 3],
            [601, null, 5],
        ];

        foreach ($ladder as $order => [$from, $to, $coins]) {
            WalletSchemeTier::create([
                'scheme_id' => $scheme->id,
                'tier_order' => $order + 1,
                'appointments_from' => $from,
                'appointments_to' => $to,
                // The pre-band column is still written, equal to the band's
                // start, so anything reading the old shape keeps working.
                'appointments_required' => $from,
                'coins_awarded' => $coins,
            ]);
        }

        $this->components->twoColumnDetail('coin ladder', '4 bands · 1 → 5 coins per appointment');
    }

    /**
     * The master catalogue every salon builds its menu from.
     */
    private function seedCatalog(): void
    {
        $catalog = [
            'Hair' => [
                ["Men's Haircut", 30],
                ["Women's Haircut", 45],
                ['Hair Colour', 90],
                ['Keratin Treatment', 120],
                ['Head Massage', 30],
                ['Beard Trim', 20],
            ],
            'Skin' => [
                ['Classic Facial', 45],
                ['Gold Facial', 60],
                ['Clean Up', 30],
                ['De-Tan Pack', 30],
            ],
            'Nails' => [
                ['Manicure', 40],
                ['Pedicure', 50],
                ['Gel Polish', 45],
                ['Nail Art', 60],
            ],
            'Spa' => [
                ['Aroma Body Massage', 60],
                ['Deep Tissue Massage', 75],
                ['Foot Reflexology', 45],
            ],
            'Grooming' => [
                ['Threading', 15],
                ['Waxing — Half Arms', 25],
                ['Waxing — Full Legs', 45],
            ],
        ];

        $templates = 0;
        $order = 0;

        foreach ($catalog as $categoryName => $entries) {
            $category = ServiceCategory::updateOrCreate(
                ['name' => $categoryName],
                [
                    'is_custom' => false,
                    'is_active' => true,
                    'display_order' => ++$order,
                ]
            );

            $this->catalogCategoryIds[] = $category->id;

            foreach ($entries as [$name, $minutes]) {
                ServiceTemplate::updateOrCreate(
                    ['name' => $name, 'category_id' => $category->id],
                    [
                        'estimated_duration_minutes' => $minutes,
                        'is_custom' => false,
                        'is_active' => true,
                    ]
                );
                $templates++;
            }
        }

        // One custom template waiting to be promoted, so the catalogue screen
        // has a decision on it rather than just a list.
        $spa = ServiceCategory::where('name', 'Spa')->first();
        ServiceTemplate::updateOrCreate(
            ['name' => 'Bridal Glow Ritual', 'category_id' => $spa->id],
            [
                'estimated_duration_minutes' => 150,
                'is_custom' => true,
                'is_active' => true,
                'promoted_to_standard_at' => null,
            ]
        );

        $merged = $this->mergeStrayCatalog();

        $this->components->twoColumnDetail(
            'catalogue',
            count($catalog) . " categories · {$templates} services · 1 custom awaiting promotion"
            . ($merged ? " · {$merged} stray entr(y/ies) merged away" : '')
        );
    }

    /**
     * Fold earlier catalogue attempts into the one above.
     *
     * Old testing left categories like "Nail" and "SPA" holding templates with
     * the same names as the real ones. A salon's menu would then be grouped
     * under a category nobody maintains — which is what the customer app shows
     * as a section heading.
     */
    private function mergeStrayCatalog(): int
    {
        $mine = ServiceTemplate::whereIn('category_id', $this->catalogCategoryIds)
            ->get()
            ->keyBy('name');

        $strays = ServiceTemplate::whereNotIn('category_id', $this->catalogCategoryIds)->get();
        $merged = 0;

        foreach ($strays as $stray) {
            $replacement = $mine->get($stray->name);

            if ($replacement) {
                // Anything still sold from the stray moves to the real one.
                Service::where('template_id', $stray->id)
                    ->update(['template_id' => $replacement->id]);
                $stray->delete();
                $merged++;

                continue;
            }

            // No equivalent, but nothing sells it either — it is just clutter.
            if (! Service::where('template_id', $stray->id)->exists()) {
                $stray->delete();
                $merged++;
            }
        }

        // A category with nothing left in it has no reason to be on the menu.
        foreach (ServiceCategory::whereNotIn('id', $this->catalogCategoryIds)->get() as $category) {
            if (! ServiceTemplate::where('category_id', $category->id)->exists()) {
                $category->delete();
                $merged++;
            }
        }

        return $merged;
    }

    private function seedBanners(): void
    {
        Banner::query()->delete();

        $banners = [
            ['Monsoon Glow — 20% off all facials', 'platform', null, true, 0],
            ['Bridal season is here', 'platform', null, true, 0],
            ['Pune: new salons every week', 'city', 'Pune', true, 0],
            ['Refer a friend, both get ₹200', 'platform', null, false, -40],
        ];

        foreach ($banners as [$title, $scope, $cityName, $active, $startOffset]) {
            Banner::create([
                'title' => $title,
                'image_url' => 'https://placehold.co/1200x400/9C54F2/FFFFFF/png?text=' . urlencode($title),
                'target_scope' => $scope,
                'target_city_id' => $cityName ? ($this->cities[$cityName]->id ?? null) : null,
                'target_salon_id' => null,
                'start_date' => Carbon::today()->addDays($startOffset)->toDateString(),
                'end_date' => Carbon::today()->addDays($startOffset + 60)->toDateString(),
                'is_active' => $active,
                'action_url' => null,
            ]);
        }

        $this->components->twoColumnDetail('banners', '4 · 3 running, 1 expired');
    }

    // --------------------------------------------------------------- people

    /** @return array<int, User> */
    private function seedCustomers(): array
    {
        $people = [
            ['Aarti Deshpande', 'female'], ['Rohan Kulkarni', 'male'],
            ['Sneha Patil', 'female'], ['Vikram Joshi', 'male'],
            ['Meera Shah', 'female'], ['Aditya Rane', 'male'],
            ['Pooja Nair', 'female'], ['Karan Mehta', 'male'],
            ['Ishita Bhat', 'female'], ['Nikhil Sawant', 'male'],
            ['Tanvi Gokhale', 'female'], ['Siddharth Iyer', 'male'],
            ['Ananya Reddy', 'female'], ['Manish Chauhan', 'male'],
        ];

        $made = [];

        foreach ($people as $index => [$name, $gender]) {
            $made[] = User::updateOrCreate(
                ['phone' => self::PHONE_PREFIX . str_pad((string) ($index + 1), 8, '0', STR_PAD_LEFT)],
                [
                    'name' => $name,
                    'password_hash' => Hash::make('demo1234'),
                    'role' => 'customer',
                    'gender' => $gender,
                    'is_active' => true,
                ]
            );
        }

        $this->components->twoColumnDetail(
            count($made) . ' customers',
            self::PHONE_PREFIX . '00000001 … ' . self::PHONE_PREFIX . '00000' . str_pad((string) count($made), 3, '0', STR_PAD_LEFT)
        );

        return $made;
    }

    private function seedCollaborators(): void
    {
        $people = [
            ['Prashant Gaikwad', '9700000001'],
            ['Ritu Malhotra', '9700000002'],
        ];

        foreach ($people as [$name, $phone]) {
            User::updateOrCreate(
                ['phone' => $phone],
                [
                    'name' => $name,
                    'password_hash' => Hash::make('demo1234'),
                    'role' => 'collaborator',
                    'is_active' => true,
                ]
            );
        }

        $this->components->twoColumnDetail('collaborators', '2 · 9700000001, 9700000002');
    }

    // --------------------------------------------------------------- salons

    /**
     * Who trades, where, how they pay, and how well they are doing.
     *
     * @return array<int, array<string, mixed>>
     */
    private function salonBlueprints(): array
    {
        return [
            [
                'name' => 'Glow Up Studio', 'lat' => 18.5362, 'lng' => 73.8939, 'city' => 'Pune', 'phone' => '9112002049',
                'owner' => 'Sanjay Deshmukh', 'status' => 'active',
                'billing' => 'growth', 'staff' => 4, 'busyness' => 5,
                'rating' => 4.7, 'gender' => 'Unisex',
                'address' => 'Shop 4, Lane 6, Koregaon Park, Pune',
                'about' => 'Full-service unisex salon in Koregaon Park. Known for colour and bridal work.',
            ],
            [
                'name' => 'Elite Cuts', 'lat' => 19.0544, 'lng' => 72.8266, 'city' => 'Mumbai', 'phone' => '9168281183',
                'owner' => 'Farhan Qureshi', 'status' => 'active',
                'billing' => 'commission', 'rate' => 12.0, 'staff' => 3, 'busyness' => 4,
                'rating' => 4.4, 'gender' => 'Men Only',
                'address' => '12 Hill Road, Bandra West, Mumbai',
                'about' => 'Men\'s grooming bar. Walk in for a fade, stay for the beard work.',
            ],
            [
                'name' => 'Serenity Spa & Salon', 'lat' => 12.9784, 'lng' => 77.6408, 'city' => 'Bangalore', 'phone' => '9112002047',
                'owner' => 'Lakshmi Menon', 'status' => 'active',
                'billing' => 'commission', 'rate' => 15.0, 'staff' => 4, 'busyness' => 4,
                'rating' => 4.8, 'gender' => 'Women Only',
                'address' => '221 Indiranagar 100ft Road, Bangalore',
                'about' => 'Quiet spa-first studio. Massages, facials and long appointments.',
            ],
            [
                'name' => 'The Style Loft', 'lat' => 18.559, 'lng' => 73.7868, 'city' => 'Pune', 'phone' => '9112002046',
                'owner' => 'Neha Kulkarni', 'status' => 'active',
                'billing' => 'starter', 'staff' => 3, 'busyness' => 3,
                'rating' => 4.2, 'gender' => 'Unisex',
                'address' => '3rd Floor, Baner Road, Pune',
                'about' => 'Neighbourhood salon with a loyal regular crowd.',
            ],
            [
                'name' => 'Urban Trim', 'lat' => 20.0059, 'lng' => 73.7749, 'city' => 'Nashik', 'phone' => '9811000005',
                'owner' => 'Amol Pawar', 'status' => 'active',
                'billing' => 'starter', 'staff' => 2, 'busyness' => 2,
                'rating' => 3.9, 'gender' => 'Men Only',
                'address' => 'Near College Road, Nashik',
                'about' => 'Small, fast and cheap. Two chairs, no waiting.',
            ],
            // Lapsed: the lockdown story. Trades, then stops being bookable.
            [
                'name' => 'Bliss Beauty Bar', 'lat' => 19.1364, 'lng' => 72.8296, 'city' => 'Mumbai', 'phone' => '9811000006',
                'owner' => 'Reshma Shaikh', 'status' => 'active',
                'billing' => 'lapsed', 'staff' => 2, 'busyness' => 2,
                'rating' => 4.1, 'gender' => 'Women Only',
                'address' => 'Andheri West, Mumbai',
                'about' => 'Beauty bar for nails, threading and quick facials.',
            ],
            // Waiting on SuperAdmin: the approval queue.
            [
                'name' => 'Scissors & Co.', 'lat' => 18.559, 'lng' => 73.8078, 'city' => 'Pune', 'phone' => '9811000007',
                'owner' => 'Vaibhav Jadhav', 'status' => 'pending_approval',
                'billing' => 'none', 'staff' => 0, 'busyness' => 0,
                'rating' => 0.0, 'gender' => 'Unisex',
                'address' => 'Aundh, Pune',
                'about' => 'New unisex salon applying to join the marketplace.',
            ],
            [
                'name' => 'Velvet Touch Salon', 'lat' => 12.9116, 'lng' => 77.6474, 'city' => 'Bangalore', 'phone' => '9811000008',
                'owner' => 'Divya Krishnan', 'status' => 'pending_approval',
                'billing' => 'none', 'staff' => 0, 'busyness' => 0,
                'rating' => 0.0, 'gender' => 'Women Only',
                'address' => 'HSR Layout, Bangalore',
                'about' => 'Ladies-only studio waiting on approval.',
            ],
        ];
    }

    /** @param array<string, mixed> $blueprint */
    private function seedSalon(array $blueprint): void
    {
        $owner = User::updateOrCreate(
            ['phone' => $blueprint['phone']],
            [
                'name' => $blueprint['owner'],
                'password_hash' => Hash::make('demo1234'),
                'role' => 'admin',
                'is_active' => true,
            ]
        );

        $city = $this->cities[$blueprint['city']] ?? reset($this->cities);
        $approved = $blueprint['status'] === 'active';

        $salon = Salon::updateOrCreate(
            ['slug' => Str::slug($blueprint['name'])],
            [
                'admin_id' => $owner->id,
                'name' => $blueprint['name'],
                'description' => $blueprint['about'],
                'address' => $blueprint['address'],
                'city_id' => $city->id,
                'pincode' => (string) random_int(400001, 411057),
                'phone_num' => $blueprint['phone'],
                'status' => $blueprint['status'],
                'gender_focus' => $blueprint['gender'],
                'submitted_by' => $owner->id,
                'approved_by' => $approved ? $this->superAdmin->id : null,
                'approved_at' => $approved ? Carbon::today()->subWeeks(self::WEEKS_OF_HISTORY) : null,
                'advance_required' => true,
                'advance_refundable' => true,
                'advance_percentage_default' => 30,
                'avg_rating' => $blueprint['rating'],
                'review_count' => 0,
                // Real neighbourhood positions, so "nearest first" orders these
                // the way a customer standing in the city would expect.
                'latitude' => $blueprint['lat'],
                'longitude' => $blueprint['lng'],
                'location_source' => 'owner',
                'cover_photo_url' => 'https://placehold.co/1200x600/1C1726/F3EBFE/png?text='
                    . urlencode($blueprint['name']),
            ]
        );

        if ($blueprint['status'] !== 'active') {
            $this->components->twoColumnDetail($salon->name, "{$blueprint['city']} · awaiting approval");

            return;
        }

        $this->seedSalonHours($salon);
        $services = $this->seedServices($salon, $blueprint['gender']);
        $this->seedStaff($salon, $blueprint['staff'], $services);
        $this->seedCombos($salon, $services);
        $this->applyBilling($salon, $blueprint);

        $this->busyness[$salon->id] = $blueprint['busyness'];
        $this->targetRating[$salon->id] = $blueprint['rating'];
        $this->tradingSalons[] = $salon;

        $this->components->twoColumnDetail(
            $salon->name,
            sprintf(
                '%s · %s · %d staff · %d services',
                $blueprint['city'],
                $this->billingSummary($blueprint),
                $blueprint['staff'],
                count($services)
            )
        );
    }

    /**
     * Remove salons left over from earlier testing.
     *
     * "salon1" and "Test 4" in a list a client is looking at undoes the work
     * the rest of this command does. Their owner accounts stay, because the
     * blueprints above reuse those same logins.
     */
    private function retireLegacySalons(): void
    {
        $keep = array_map(
            fn ($blueprint) => Str::slug($blueprint['name']),
            $this->salonBlueprints()
        );

        $legacy = Salon::whereNotIn('slug', $keep)->get();

        foreach ($legacy as $salon) {
            $providerIds = ServiceProvider::withTrashed()->where('salon_id', $salon->id)->pluck('id');

            DB::table('provider_services')->whereIn('provider_id', $providerIds)->delete();
            DB::table('provider_working_hours')->whereIn('provider_id', $providerIds)->delete();
            DB::table('provider_leaves')->whereIn('provider_id', $providerIds)->delete();
            DB::table('service_providers')->whereIn('id', $providerIds)->delete();

            foreach (Combo::where('salon_id', $salon->id)->get() as $combo) {
                $combo->services()->detach();
                $combo->delete();
            }

            DB::table('coupons')->where('salon_id', $salon->id)->delete();
            DB::table('services')->where('salon_id', $salon->id)->delete();
            DB::table('salon_working_hours')->where('salon_id', $salon->id)->delete();
            DB::table('salon_media')->where('salon_id', $salon->id)->delete();
            DB::table('salon_commission_rates')->where('salon_id', $salon->id)->delete();
            DB::table('salon_subscriptions')->where('salon_id', $salon->id)->delete();
            DB::table('salon_closures')->where('salon_id', $salon->id)->delete();
            DB::table('carts')->where('salon_id', $salon->id)->delete();
            DB::table('banners')->where('target_salon_id', $salon->id)->delete();

            // A category this salon once proposed outlives it — the catalogue
            // is platform-wide, so it is disowned rather than deleted.
            foreach (['service_categories', 'service_templates'] as $catalogTable) {
                DB::table($catalogTable)
                    ->where('created_by_salon_id', $salon->id)
                    ->update(['created_by_salon_id' => null]);
            }

            DB::table('salons')->where('id', $salon->id)->delete();
        }

        if ($legacy->isNotEmpty()) {
            $this->components->twoColumnDetail(
                'retired',
                $legacy->count() . ' old test salon(s): ' . $legacy->pluck('name')->join(', ')
            );
        }
    }

    /** @param array<string, mixed> $blueprint */
    private function billingSummary(array $blueprint): string
    {
        return match ($blueprint['billing']) {
            'commission' => "Commission Model {$blueprint['rate']}%",
            'growth' => 'Growth plan',
            'starter' => 'Starter plan',
            'lapsed' => 'plan lapsed',
            default => 'no plan',
        };
    }

    /** @param array<string, mixed> $blueprint */
    private function applyBilling(Salon $salon, array $blueprint): void
    {
        SalonSubscription::where('salon_id', $salon->id)->update(['status' => 'cancelled']);

        if ($blueprint['billing'] === 'commission') {
            app(CommissionService::class)->activate(
                $salon,
                $blueprint['rate'],
                $this->superAdmin,
                'Agreed at onboarding.'
            );

            return;
        }

        $salon->forceFill([
            'commission_opt_in' => false,
            'commission_percentage' => null,
            'commission_rate_effective_from' => null,
        ])->save();

        $plan = $blueprint['billing'] === 'growth' ? $this->growth : $this->starter;

        // A lapsed plan is what puts a salon behind the lock screen, so it ends
        // in the past rather than the future.
        $lapsed = $blueprint['billing'] === 'lapsed';

        SalonSubscription::create([
            'salon_id' => $salon->id,
            'plan_id' => $plan->id,
            'billing_type' => BillingModel::SUBSCRIPTION,
            'plan_price_snapshot' => $plan->price,
            'start_date' => $lapsed
                ? Carbon::today()->subDays(34)
                : Carbon::today()->subDays(random_int(3, 20)),
            'end_date' => $lapsed
                ? Carbon::yesterday()
                : Carbon::today()->addDays(random_int(10, 27)),
            'status' => $lapsed ? 'expired' : 'active',
        ]);
    }

    private function seedSalonHours(Salon $salon): void
    {
        SalonWorkingHour::where('salon_id', $salon->id)->delete();

        // Closed one weekday, open late at the weekend — the pattern a real
        // salon runs, and what makes the slot picker interesting.
        $closedDay = random_int(1, 3);

        for ($day = 0; $day <= 6; $day++) {
            $weekend = in_array($day, [0, 6], true);

            SalonWorkingHour::create([
                'salon_id' => $salon->id,
                'day_of_week' => $day,
                'is_closed' => $day === $closedDay,
                'open_time' => $weekend ? '09:00:00' : '10:00:00',
                'close_time' => $weekend ? '21:00:00' : '20:00:00',
            ]);
        }
    }

    /** @return array<string, Service> */
    private function seedServices(Salon $salon, string $genderFocus): array
    {
        // Priced so the same service costs more in Mumbai than in Nashik.
        $menu = [
            "Men's Haircut" => 350, 'Beard Trim' => 200, 'Head Massage' => 450,
            "Women's Haircut" => 700, 'Hair Colour' => 2200, 'Keratin Treatment' => 4500,
            'Classic Facial' => 900, 'Gold Facial' => 1600, 'Clean Up' => 600,
            'De-Tan Pack' => 500, 'Manicure' => 550, 'Pedicure' => 750,
            'Gel Polish' => 900, 'Nail Art' => 1200, 'Aroma Body Massage' => 2000,
            'Deep Tissue Massage' => 2600, 'Foot Reflexology' => 1100,
            'Threading' => 100, 'Waxing — Half Arms' => 400, 'Waxing — Full Legs' => 900,
        ];

        // A men's bar does not sell facials to nobody; the menu follows the
        // room, which is what makes the customer app's filters mean something.
        $skip = match ($genderFocus) {
            'Men Only' => ['Gel Polish', 'Nail Art', 'Gold Facial', 'Waxing — Full Legs', 'Keratin Treatment'],
            'Women Only' => ['Beard Trim'],
            default => [],
        };

        $made = [];
        $order = 0;

        foreach ($menu as $name => $price) {
            if (in_array($name, $skip, true)) {
                continue;
            }

            // Scoped to this command's categories: a stray template of the
            // same name would group the salon's menu under a dead heading.
            $template = ServiceTemplate::whereIn('category_id', $this->catalogCategoryIds)
                ->where('name', $name)
                ->first();

            if (! $template) {
                continue;
            }

            $made[$name] = Service::updateOrCreate(
                ['salon_id' => $salon->id, 'template_id' => $template->id],
                [
                    'price' => $price,
                    'advance_percentage' => 30,
                    'will_refund_advance_if_cancelled' => true,
                    'is_active' => true,
                    'display_order' => ++$order,
                    'gender_focus' => 'Unisex',
                ]
            );
        }

        return $made;
    }

    /** @param array<string, Service> $services */
    private function seedStaff(Salon $salon, int $count, array $services): array
    {
        $names = [
            'Rajesh Bhosale', 'Priya Salunkhe', 'Imran Sheikh', 'Kavita More',
            'Sameer Dixit', 'Anjali Wagh', 'Deepak Yadav', 'Shweta Kadam',
        ];

        $specialisms = ['Hair & Colour', 'Skin & Facials', 'Nails', 'Spa & Massage'];
        $made = [];

        for ($i = 0; $i < $count; $i++) {
            $name = $names[($i + crc32($salon->slug)) % count($names)];
            $phone = '97' . substr((string) crc32($salon->slug . $i), 0, 8);

            $user = User::updateOrCreate(
                ['phone' => $phone],
                [
                    'name' => $name,
                    'password_hash' => Hash::make('demo1234'),
                    'role' => 'service_provider',
                    'is_active' => true,
                ]
            );

            $provider = ServiceProvider::updateOrCreate(
                ['user_id' => $user->id, 'salon_id' => $salon->id],
                [
                    'specialization' => $specialisms[$i % count($specialisms)],
                    'base_salary' => [18000, 22000, 26000, 30000][$i % 4],
                    'commission_percentage' => [5, 8, 10, 12][$i % 4],
                    'auto_approve_leave' => $i === 0,
                    'is_active' => true,
                    'joined_at' => Carbon::today()->subMonths(random_int(4, 20)),
                ]
            );

            $this->seedProviderHours($provider);

            // Everyone can do everything here — a demo where half the staff
            // cannot take a booking makes the slot picker look broken.
            DB::table('provider_services')->where('provider_id', $provider->id)->delete();

            foreach ($services as $service) {
                DB::table('provider_services')->insert([
                    'provider_id' => $provider->id,
                    'service_id' => $service->id,
                ]);
            }

            $made[] = $provider;
        }

        return $made;
    }

    private function seedProviderHours(ServiceProvider $provider): void
    {
        DB::table('provider_working_hours')->where('provider_id', $provider->id)->delete();

        $off = random_int(1, 5);

        for ($day = 0; $day <= 6; $day++) {
            DB::table('provider_working_hours')->insert([
                'id' => (string) Str::uuid(),
                'provider_id' => $provider->id,
                'day_of_week' => $day,
                'is_weekly_off' => $day === $off,
                'shift_start' => '10:00:00',
                'shift_end' => '20:00:00',
                'break_start' => '14:00:00',
                'break_end' => '14:45:00',
            ]);
        }
    }

    /** @param array<string, Service> $services */
    private function seedCombos(Salon $salon, array $services): void
    {
        foreach (Combo::where('salon_id', $salon->id)->get() as $existing) {
            $existing->services()->detach();
            $existing->delete();
        }

        $combos = [
            'Groom Ready' => ["Men's Haircut", 'Beard Trim', 'Clean Up'],
            'Weekend Reset' => ['Head Massage', 'Foot Reflexology'],
            'Party Perfect' => ["Women's Haircut", 'Gold Facial'],
            'Hands & Feet' => ['Manicure', 'Pedicure'],
        ];

        foreach ($combos as $name => $lines) {
            $available = array_filter($lines, fn ($line) => isset($services[$line]));

            // A combo missing half its services would price wrong; skip it.
            if (count($available) !== count($lines)) {
                continue;
            }

            $combo = Combo::create([
                'salon_id' => $salon->id,
                'name' => $name,
                'advance_percentage' => 30,
                'will_refund_advance_if_cancelled' => true,
                'is_active' => true,
            ]);

            foreach ($lines as $line) {
                $service = $services[$line];
                $combo->services()->attach($service->id, [
                    // A combo is worth having only if it saves the customer
                    // something, so each line comes off about 15%.
                    'combo_special_price' => round((float) $service->price * 0.85, 2),
                ]);
            }
        }
    }

    // -------------------------------------------------------------- trading

    /**
     * Weeks of completed work, with deliberate pairings.
     *
     * Cart suggestions are mined from what a salon actually sells together, so
     * random baskets would leave that feature with nothing to show.
     */
    private function seedHistory(Salon $salon): void
    {
        $services = $this->menuOf($salon);
        $providers = ServiceProvider::where('salon_id', $salon->id)->where('is_active', true)->get();
        $checkIn = app(AppointmentCheckInService::class);
        $owner = User::find($salon->admin_id);

        if ($providers->isEmpty() || empty($services)) {
            return;
        }

        $baskets = $this->basketsFor($services);
        $made = 0;
        $cancelled = 0;
        $noShows = 0;

        for ($week = self::WEEKS_OF_HISTORY; $week >= 0; $week--) {
            $perWeek = $this->busyness[$salon->id] * 2;

            for ($nth = 0; $nth < $perWeek; $nth++) {
                $date = Carbon::today()->subWeeks($week)->startOfWeek()->addDays($nth % 6);

                if ($date->isFuture() || $date->isToday()) {
                    continue;
                }

                $basket = $baskets[($made + $nth) % count($baskets)];
                $provider = $providers[$made % $providers->count()];
                $customer = $this->customers[($made * 3) % count($this->customers)];
                $walkIn = $made % 6 === 5;

                $appointment = $this->createAppointment(
                    $salon,
                    $customer,
                    $provider,
                    $date,
                    sprintf('%02d:%02d:00', 10 + ($made % 9), ($made % 2) * 30),
                    array_map(fn ($n) => $services[$n], $basket),
                    $walkIn ? 'walk_in' : 'online'
                );

                // A believable week has a few that never happened.
                if ($made % 17 === 16) {
                    $this->markCancelled($appointment, $customer);
                    $cancelled++;
                    $made++;
                    continue;
                }

                if ($made % 23 === 22) {
                    $appointment->forceFill(['status' => 'no_show', 'no_show_at' => $date])->save();
                    $noShows++;
                    $made++;
                    continue;
                }

                // Every third visit picked up something extra in the chair.
                if ($made % 3 === 0 && isset($services['Head Massage'])) {
                    app(AppointmentCheckInService::class)->addExtraService(
                        $appointment,
                        $services['Head Massage'],
                        $providers->random()->id,
                        $owner ?? $this->superAdmin
                    );
                }

                $checkIn->collectPaymentAndComplete(
                    $appointment->fresh($checkIn->relations()),
                    $made % 2 === 0 ? 'upi' : 'cash',
                    $owner ?? $this->superAdmin
                );

                if (! $walkIn && $made % 4 === 0) {
                    $this->leaveReview($appointment, $customer, $salon);
                }

                $made++;
            }
        }

        $this->refreshRating($salon);

        $this->components->twoColumnDetail(
            "  {$salon->name}",
            sprintf('%d appointments · %d cancelled · %d no-show', $made, $cancelled, $noShows)
        );
    }

    /**
     * Today, mid-service and still to come.
     *
     * The partner app's home screen is the first thing a demo opens, so it
     * needs a booking to scan, one already in the chair, and one waiting.
     */
    private function seedTodaysBoard(Salon $salon): void
    {
        $services = $this->menuOf($salon);
        $providers = ServiceProvider::where('salon_id', $salon->id)->where('is_active', true)->get();

        if ($providers->isEmpty() || empty($services)) {
            return;
        }

        $names = array_keys($services);
        $slots = [
            ['09:30:00', 'completed'],
            ['11:00:00', 'in_progress'],
            ['12:30:00', 'scheduled'],
            ['15:00:00', 'scheduled'],
            ['17:30:00', 'scheduled'],
        ];

        foreach ($slots as $i => [$time, $status]) {
            $appointment = $this->createAppointment(
                $salon,
                $this->customers[($i * 5) % count($this->customers)],
                $providers[$i % $providers->count()],
                Carbon::today(),
                $time,
                [$services[$names[$i % count($names)]]],
                'online',
                $status === 'completed' ? 'in_progress' : $status
            );

            if ($status === 'completed') {
                app(AppointmentCheckInService::class)->collectPaymentAndComplete(
                    $appointment->fresh(app(AppointmentCheckInService::class)->relations()),
                    'upi',
                    User::find($salon->admin_id) ?? $this->superAdmin
                );
            }
        }
    }

    /** Bookings still to come, so the calendar is not empty ahead of today. */
    private function seedUpcoming(Salon $salon): void
    {
        $services = $this->menuOf($salon);
        $providers = ServiceProvider::where('salon_id', $salon->id)->where('is_active', true)->get();

        if ($providers->isEmpty() || empty($services)) {
            return;
        }

        $names = array_keys($services);

        for ($i = 1; $i <= $this->busyness[$salon->id] * 2; $i++) {
            $this->createAppointment(
                $salon,
                $this->customers[($i * 7) % count($this->customers)],
                $providers[$i % $providers->count()],
                Carbon::today()->addDays(($i % 9) + 1),
                sprintf('%02d:00:00', 10 + ($i % 8)),
                [$services[$names[($i * 3) % count($names)]]],
                'online',
                'scheduled'
            );
        }
    }

    private function seedLeave(Salon $salon): void
    {
        $providers = ServiceProvider::where('salon_id', $salon->id)->get();

        if ($providers->isEmpty()) {
            return;
        }

        // Only paid and unpaid exist; unpaid is what shows up as a deduction
        // on the payslip, so the demo needs at least one of each.
        $rows = [
            [$providers->first(), Carbon::today()->addDays(4), 'paid', 'pending', 'Family function'],
            [$providers->first(), Carbon::today()->subDays(9), 'paid', 'approved', 'Fever'],
        ];

        if ($providers->count() > 1) {
            $rows[] = [$providers[1], Carbon::today()->addDays(11), 'unpaid', 'pending', 'Travelling home'];
            $rows[] = [$providers[1], Carbon::today()->subDays(20), 'unpaid', 'approved', 'Personal'];
        }

        foreach ($rows as [$provider, $date, $type, $status, $reason]) {
            ProviderLeave::create([
                'provider_id' => $provider->id,
                'leave_date' => $date->toDateString(),
                'leave_type' => $type,
                'is_full_day' => true,
                'reason' => $reason,
                'status' => $status,
                'reviewed_by' => $status === 'approved' ? $salon->admin_id : null,
                'reviewed_at' => $status === 'approved' ? $date->copy()->subDays(2) : null,
            ]);
        }
    }

    // ---------------------------------------------------------------- money

    /**
     * Payout runs in three states, on both rhythms.
     *
     * Older cycles are settled, the most recent one is left open — which is
     * what a payouts screen looks like on any given morning, and it leaves
     * SuperAdmin something to actually approve during the demo.
     */
    private function seedPayouts(): void
    {
        $payouts = app(PayoutService::class);
        $built = 0;

        // Weekly, for salons on a Subscription Plan.
        for ($week = 5; $week >= 0; $week--) {
            $result = $payouts->generateWeekly(Carbon::today()->subWeeks($week));
            $built += $result['payouts'];
        }

        // Monthly, for salons on the Commission Model.
        for ($month = 3; $month >= 0; $month--) {
            $result = $payouts->generateMonthly(Carbon::today()->subMonthsNoOverflow($month));
            $built += $result['payouts'];
        }

        $rows = DB::table('salon_payouts')->orderBy('cycle_start_date')->get();
        $thisWeek = Carbon::today()->startOfWeek()->toDateString();
        $thisMonth = Carbon::today()->startOfMonth()->toDateString();

        $distributed = 0;
        $approved = 0;
        $pending = 0;

        foreach ($rows as $row) {
            $isCurrent = $row->cycle_start_date >= ($row->cycle_type === PayoutCycle::MONTHLY ? $thisMonth : $thisWeek);
            $isPrevious = ! $isCurrent && $row->cycle_start_date >= Carbon::today()
                ->subWeek()->startOfWeek()->toDateString();

            $payout = \App\Models\SalonPayout::find($row->id);

            if ($isCurrent) {
                $pending++;
                continue;
            }

            // The one just gone is signed off but not yet paid, so the demo has
            // a row sitting at each stage.
            $payouts->approve($payout, $this->superAdmin);

            if ($isPrevious) {
                $approved++;
                continue;
            }

            $payouts->markDistributed(
                $payout->fresh(),
                $this->superAdmin,
                'NEFT' . random_int(10000000, 99999999),
                null
            );
            $distributed++;
        }

        $this->components->twoColumnDetail(
            'payouts',
            "{$built} cycles · {$distributed} distributed, {$approved} approved, {$pending} pending"
        );
    }

    /**
     * Coins actually spent, not just earned.
     *
     * A wallet showing only credits looks like a counter rather than a
     * currency. One salon settles coins against the commission it owes, another
     * puts them towards its plan — the only two things coins can be spent on.
     */
    private function seedWalletRedemptions(): void
    {
        $wallet = app(WalletService::class);
        $spent = 0;

        foreach ($this->tradingSalons as $salon) {
            $fresh = $salon->fresh();

            if ($fresh->isOnCommissionModel()) {
                // Against an open month, which is when a salon would really do
                // it — the commission has been calculated but not yet taken.
                $payout = \App\Models\SalonPayout::where('salon_id', $fresh->id)
                    ->where('status', PayoutService::STATUS_PENDING)
                    ->where('commission_deducted', '>', 0)
                    ->orderByDesc('cycle_start_date')
                    ->first();

                if (! $payout) {
                    continue;
                }

                $quote = $wallet->quote(
                    $fresh->id,
                    (float) $payout->commission_deducted - (float) $payout->wallet_redeemed_amount
                );

                // Spend about half the balance, so there is still some left to
                // look at on the wallet screen.
                $coins = (int) floor($quote['coins'] / 2);

                if ($coins < 1) {
                    continue;
                }

                $result = $wallet->redeemAgainstCommission($fresh->id, $payout, $coins, $this->superAdmin);

                $payout->forceFill([
                    'wallet_redeemed_amount' => (float) $payout->wallet_redeemed_amount + $result['value'],
                ])->save();

                app(PayoutService::class)->calculate(
                    $fresh->id,
                    Carbon::parse($payout->cycle_start_date),
                    Carbon::parse($payout->cycle_end_date),
                    $payout->cycle_type
                );

                $spent += $coins;

                continue;
            }

            $subscription = $fresh->currentSubscription;

            if (! $subscription) {
                continue;
            }

            $quote = $wallet->quote($fresh->id, (float) $subscription->plan_price_snapshot);
            $coins = (int) floor($quote['coins'] / 2);

            if ($coins < 1) {
                continue;
            }

            $wallet->redeemForSubscription(
                $fresh->id,
                $coins,
                (float) $subscription->plan_price_snapshot,
                $this->superAdmin,
                $subscription,
                'Applied to the ' . ($subscription->plan->name ?? 'plan') . ' renewal'
            );

            $spent += $coins;
        }

        $this->components->twoColumnDetail('coins spent', "{$spent} redeemed against commission and renewals");
    }

    /**
     * Payslips for the month just gone, so payroll opens onto real numbers.
     */
    private function seedPayroll(): void
    {
        $month = Carbon::today()->subMonthNoOverflow()->startOfMonth();
        $made = 0;

        foreach ($this->tradingSalons as $salon) {
            foreach (ServiceProvider::where('salon_id', $salon->id)->get() as $provider) {
                $base = (float) $provider->base_salary;
                $workingDays = 26;
                $dailyRate = round($base / $workingDays, 2);
                $unpaidDays = $made % 5 === 0 ? 1.0 : 0.0;

                $commission = round(
                    (float) DB::table('appointment_services')
                        ->join('appointments', 'appointments.id', '=', 'appointment_services.appointment_id')
                        ->where('appointment_services.serving_provider_id', $provider->id)
                        ->where('appointments.status', 'completed')
                        ->whereBetween('appointments.appointment_date', [
                            $month->toDateString(),
                            $month->copy()->endOfMonth()->toDateString(),
                        ])
                        ->sum('appointment_services.price_at_booking')
                    * (float) $provider->commission_percentage / 100,
                    2
                );

                $deduction = round($dailyRate * $unpaidDays, 2);

                DB::table('salary_payouts')->insert([
                    'id' => (string) Str::uuid(),
                    'provider_id' => $provider->id,
                    'salon_id' => $salon->id,
                    'salary_month' => $month->toDateString(),
                    'base_salary_snapshot' => $base,
                    'commission_percentage_snapshot' => $provider->commission_percentage,
                    'commission_earned' => $commission,
                    'working_days_in_month' => $workingDays,
                    'daily_rate' => $dailyRate,
                    'paid_leave_days' => 0,
                    'unpaid_leave_days' => $unpaidDays,
                    'unpaid_leave_deduction' => $deduction,
                    'other_adjustments' => 0,
                    'total_payable' => round($base - $deduction + $commission, 2),
                    // Most are paid; one salon's are still open, so the screen
                    // has a button worth pressing.
                    'status' => $made % 7 === 0 ? 'pending' : 'paid',
                    'paid_by' => $made % 7 === 0 ? null : $salon->admin_id,
                    'paid_at' => $made % 7 === 0 ? null : $month->copy()->endOfMonth()->addDay(),
                    'payment_reference' => $made % 7 === 0 ? null : 'SAL' . random_int(100000, 999999),
                    'calculated_at' => now(),
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);

                $made++;
            }
        }

        $this->components->twoColumnDetail('payroll', "{$made} payslips for " . $month->format('F Y'));
    }

    /**
     * Clear away what earlier testing left lying around.
     *
     * A catalogue with "Test Category" in it, or staff logins pointing at a
     * salon that no longer exists, are exactly the details that get noticed
     * during a demo.
     */
    private function tidyLeftovers(): void
    {
        // Staff whose salon was retired can still log in and would land nowhere.
        $orphaned = User::where('role', 'service_provider')
            ->whereNotIn('id', ServiceProvider::query()->select('user_id'))
            ->update(['is_active' => false]);

        // Same for owners: an account with no salon behind it is a dead end.
        $ownerless = User::where('role', 'admin')
            ->whereNotIn('id', Salon::query()->select('admin_id'))
            ->update(['is_active' => false]);

        $this->components->twoColumnDetail(
            'tidied',
            "{$orphaned} orphaned staff and {$ownerless} ownerless admin login(s) disabled"
        );
    }

    // --------------------------------------------------------------- queues

    private function seedEnquiries(): void
    {
        SalonEnquiry::query()->delete();

        $collaborator = User::where('role', 'collaborator')->first();

        $rows = [
            ['Hair Story', 'Ganesh Pawar', '9812000001', 'Pune', 'Two chairs, want to start taking online bookings.', 'new', null],
            ['Blush Beauty Lounge', 'Sarita Jain', '9812000002', 'Mumbai', 'Interested in the commission model — no upfront fee.', 'new', null],
            ['Trim & Trend', 'Aslam Khan', '9812000003', 'Nashik', 'Called about pricing, wants a callback this week.', 'assigned', $collaborator?->id],
            ['The Barber Room', 'Nitin Salvi', '9812000004', 'Pune', 'Ready to onboard, needs help with the paperwork.', 'assigned', $collaborator?->id],
            ['Aura Wellness', 'Preeti Rao', '9812000005', 'Bangalore', 'Signed up last week.', 'onboarded', $collaborator?->id],
        ];

        foreach ($rows as $i => [$salonName, $ownerName, $phone, $city, $message, $status, $assigned]) {
            $enquiry = SalonEnquiry::create([
                'salon_name' => $salonName,
                'owner_name' => $ownerName,
                'phone' => $phone,
                'city' => $city,
                'message' => $message,
                'status' => $status,
                'assigned_collaborator_id' => $assigned,
                'assigned_at' => $assigned ? Carbon::today()->subDays($i + 1) : null,
            ]);

            // A queue where everything arrived at once reads as seeded.
            $enquiry->forceFill([
                'created_at' => Carbon::today()->subDays($i + 2),
                'updated_at' => Carbon::today()->subDays($i),
            ])->save();
        }

        $this->components->twoColumnDetail('enquiries', '5 · 2 new, 2 assigned, 1 onboarded');
    }

    /**
     * Requests waiting on SuperAdmin, so the subscriptions screen opens with
     * something to decide rather than an empty panel.
     */
    private function seedSubscriptionRequests(): void
    {
        $lapsed = Salon::where('slug', Str::slug('Bliss Beauty Bar'))->first();
        $starterSalon = Salon::where('slug', Str::slug('Urban Trim'))->first();

        if ($lapsed) {
            // Paid to renew; the receipt is waiting to be checked.
            SubscriptionPaymentRequest::create([
                'salon_id' => $lapsed->id,
                'subscription_plan_id' => $this->starter->id,
                'billing_type' => BillingModel::SUBSCRIPTION,
                'screenshot_url' => 'https://placehold.co/600x900/E8F5E9/2E7D32/png?text=UPI+Receipt+%E2%82%B91999',
                'status' => 'pending',
                'created_at' => Carbon::today()->subDay(),
                'updated_at' => Carbon::today()->subDay(),
            ]);
        }

        if ($starterSalon) {
            // Asking to move to the Commission Model. Nothing was paid, so
            // there is no receipt — only a percentage to agree.
            SubscriptionPaymentRequest::create([
                'salon_id' => $starterSalon->id,
                'subscription_plan_id' => $this->growth->id,
                'billing_type' => BillingModel::COMMISSION,
                'screenshot_url' => null,
                'status' => 'pending',
                'created_at' => Carbon::today(),
                'updated_at' => Carbon::today(),
            ]);
        }

        $this->components->twoColumnDetail('subscription requests', '2 pending · 1 receipt, 1 commission request');
    }

    // ------------------------------------------------------------- builders

    /**
     * @param array<string, Service> $services
     * @return array<int, array<int, string>>
     */
    private function basketsFor(array $services): array
    {
        $candidates = [
            ["Men's Haircut", 'Beard Trim'],
            ["Men's Haircut"],
            ["Women's Haircut", 'Threading'],
            ['Hair Colour'],
            ['Manicure', 'Pedicure'],
            ['Gel Polish', 'Nail Art'],
            ['Classic Facial', 'Clean Up'],
            ['Aroma Body Massage'],
            ['Head Massage', 'Foot Reflexology'],
            ['Waxing — Half Arms', 'Threading'],
        ];

        $usable = array_values(array_filter(
            $candidates,
            fn ($basket) => count(array_filter($basket, fn ($n) => isset($services[$n]))) === count($basket)
        ));

        return $usable ?: [[array_key_first($services)]];
    }

    /** @param array<int, Service> $services */
    private function createAppointment(
        Salon $salon,
        User $customer,
        ServiceProvider $provider,
        Carbon $date,
        string $startTime,
        array $services,
        string $source = 'online',
        string $status = 'in_progress'
    ): Appointment {
        $total = 0.0;
        $advance = 0.0;
        $minutes = 0;

        foreach ($services as $service) {
            $price = (float) $service->price;
            $total += $price;
            $advance += round($price * (float) $service->advance_percentage / 100, 2);
            $minutes += (int) ($service->template->estimated_duration_minutes ?? 30);
        }

        $start = Carbon::parse($date->toDateString() . ' ' . $startTime);

        $appointment = Appointment::create([
            'salon_id' => $salon->id,
            'customer_id' => $source === 'walk_in' ? null : $customer->id,
            'appointed_provider_id' => $provider->id,
            'serving_provider_id' => $status === 'scheduled' ? null : $provider->id,
            'booking_source' => $source,
            'appointment_date' => $date->toDateString(),
            'start_time' => $start->format('H:i:s'),
            'end_time' => $start->copy()->addMinutes(max($minutes, 30))->format('H:i:s'),
            'status' => $status,
            'payment_option' => 'advance_only',
            'total_amount' => round($total, 2),
            'advance_amount' => round($advance, 2),
            'balance_amount' => round($total - $advance, 2),
            'walk_in_customer_name' => $source === 'walk_in' ? $customer->name : null,
            'walk_in_customer_phone' => $source === 'walk_in' ? $customer->phone : null,
            'walk_in_customer_gender' => $source === 'walk_in' ? $customer->gender : null,
            'started_at' => $status === 'in_progress' ? $start : null,
            'created_at' => $start->copy()->subDays(2),
        ]);

        foreach ($services as $service) {
            AppointmentLine::create([
                'appointment_id' => $appointment->id,
                'service_id' => $service->id,
                'price_at_booking' => (float) $service->price,
                'original_service_price' => (float) $service->price,
                'duration_minutes_at_booking' => (int) ($service->template->estimated_duration_minutes ?? 30),
                'serving_provider_id' => $status === 'scheduled' ? null : $provider->id,
                'line_status' => 'booked',
            ]);
        }

        // The advance paid at booking, written to the same ledger the live
        // gateway uses so payouts and refunds see it.
        if ($advance > 0 && $source === 'online') {
            DB::table('payments')->insert([
                'id' => (string) Str::uuid(),
                'appointment_id' => $appointment->id,
                'amount' => round($advance, 2),
                'currency' => 'INR',
                'payment_type' => 'advance',
                'payment_mode' => 'online',
                'gateway' => 'demo',
                'gateway_transaction_id' => 'pay_demo_' . Str::lower(Str::random(14)),
                'status' => 'success',
                'paid_at' => $start,
                'idempotency_key' => 'advance:' . $appointment->id,
                'created_at' => $start,
                'updated_at' => $start,
            ]);
        }

        return $appointment->fresh(['services.service.template']);
    }

    private function markCancelled(Appointment $appointment, User $customer): void
    {
        $appointment->forceFill([
            'status' => 'cancelled',
            'cancelled_by' => 'customer',
            'cancelled_by_user_id' => $customer->id,
            'cancellation_reason' => 'Something came up',
            'cancelled_at' => Carbon::parse($appointment->appointment_date)->subDay(),
        ])->save();
    }

    /**
     * A review whose score reflects how good the salon is meant to be.
     *
     * Reviews drive the displayed rating, so scattering them evenly would
     * leave every salon in the list rated the same — and a marketplace where
     * nothing is better than anything else is not worth browsing.
     */
    private function leaveReview(Appointment $appointment, User $customer, Salon $salon): void
    {
        $comments = [
            5 => 'Lovely experience, will come back.',
            4 => 'Good work, slightly long wait.',
            3 => 'Fine, nothing special.',
            2 => 'Not what I asked for, sadly.',
        ];

        $target = $this->targetRating[$salon->id] ?? 4.3;

        // A spread around the target rather than the same score every time.
        $spread = [$target + 0.6, $target, $target, $target - 0.4, $target + 0.3, $target - 0.9];
        $rating = (int) max(2, min(5, round($spread[crc32($appointment->id) % 6])));

        DB::table('reviews')->insert([
            'id' => (string) Str::uuid(),
            'appointment_id' => $appointment->id,
            'customer_id' => $customer->id,
            'salon_id' => $salon->id,
            'rating' => $rating,
            'comment' => $comments[$rating],
        ]);
    }

    private function refreshRating(Salon $salon): void
    {
        $stats = DB::table('reviews')
            ->where('salon_id', $salon->id)
            ->selectRaw('count(*) as n, avg(rating) as avg')
            ->first();

        if ($stats && $stats->n > 0) {
            $salon->forceFill([
                'review_count' => (int) $stats->n,
                'avg_rating' => round((float) $stats->avg, 1),
            ])->save();
        }
    }

    // -------------------------------------------------------------- helpers

    /** @return array<string, Service> */
    private function menuOf(Salon $salon): array
    {
        return Service::with('template')
            ->where('salon_id', $salon->id)
            ->where('is_active', true)
            ->get()
            ->keyBy(fn (Service $service) => $service->template->name ?? $service->id)
            ->all();
    }

    private function summary(): void
    {
        $wallet = app(WalletService::class);

        $this->newLine();
        $this->components->info('Ready to demo — every login uses OTP 123456');

        $this->components->twoColumnDetail('<fg=gray>SuperAdmin</>', $this->superAdmin->phone . ' (web dashboard)');

        foreach ($this->tradingSalons as $salon) {
            $balance = $wallet->walletFor($salon->id);
            $subscription = $salon->fresh()->currentSubscription;

            $this->components->twoColumnDetail(
                $salon->name . ' <fg=gray>· ' . $salon->phone_num . '</>',
                sprintf(
                    '%s · %d coins · ★%s',
                    $subscription
                        ? BillingModel::label($subscription->billing_type)
                        : 'lapsed',
                    $balance->coin_balance,
                    number_format((float) $salon->fresh()->avg_rating, 1)
                )
            );
        }

        foreach (Salon::where('status', 'pending_approval')->get() as $salon) {
            $this->components->twoColumnDetail(
                $salon->name . ' <fg=gray>· ' . $salon->phone_num . '</>',
                'waiting in the approval queue'
            );
        }

        $this->newLine();
        $this->components->twoColumnDetail('customers', self::PHONE_PREFIX . '00000001 … onwards');
        $this->components->twoColumnDetail('collaborators', '9700000001, 9700000002');
        $this->newLine();
    }
}
